package db

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// GetDB returns the global database connection.
func GetDB() *gorm.DB {
	return DB
}

// Init initializes the SQLite database connection, applies migrations,
// and ensures the initial Manager node exists.
func Init(dbPath string) {
	var err error
	DB, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	log.Println("Database connection established")

	// AutoMigrate the schemas
	err = DB.AutoMigrate(&Node{}, &ClusterConfig{}, &Stack{}, &Service{}, &Task{})
	if err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	seedInitialData()
	ensureJoinToken()
	ensureAPIToken()
}

// ensureJoinToken generates a secure random join token if one does not exist.
func ensureJoinToken() {
	var config ClusterConfig
	if err := DB.First(&config, "id = ?", "global").Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			bytes := make([]byte, 16)
			if _, err := rand.Read(bytes); err != nil {
				log.Fatalf("Failed to generate join token: %v", err)
			}
			token := hex.EncodeToString(bytes)
			config = ClusterConfig{ID: "global", JoinToken: token}
			if err := DB.Create(&config).Error; err != nil {
				log.Fatalf("Failed to save join token: %v", err)
			}
			log.Println("Generated new cluster Join Token.")
		} else {
			log.Fatalf("Error querying cluster config: %v", err)
		}
	}
}

// ensureAPIToken ensures a secure Bearer API token exists in the database.
// Priority:
//  1. If GBNT_API_TOKEN env var is set → save/update it in DB (operator override)
//  2. If token already exists in DB → load it into env (survives restarts)
//  3. If no token anywhere → generate one, save to DB, print it once to stdout
func ensureAPIToken() {
	var config ClusterConfig
	if err := DB.First(&config, "id = ?", "global").Error; err != nil {
		// ClusterConfig must exist at this point (created by ensureJoinToken).
		// If we can't read it, it's a fatal DB error.
		log.Fatalf("ensureAPIToken: cannot read cluster config: %v", err)
	}

	envToken := os.Getenv("GBNT_API_TOKEN")

	switch {
	case envToken != "" && envToken != config.APIToken:
		// Operator explicitly set a token via env → persist it in DB
		DB.Model(&ClusterConfig{}).Where("id = ?", "global").Update("api_token", envToken)
		log.Println("API Token updated from GBNT_API_TOKEN environment variable.")

	case config.APIToken != "":
		// Token already in DB → load it into the process environment so the
		// API middleware can read it from os.Getenv without further changes.
		if envToken == "" {
			os.Setenv("GBNT_API_TOKEN", config.APIToken)
			log.Println("API Token loaded from database.")
		}

	default:
		// First boot: no token in env or DB → generate a new secure token
		bytes := make([]byte, 32)
		if _, err := rand.Read(bytes); err != nil {
			log.Fatalf("Failed to generate API token: %v", err)
		}
		newToken := hex.EncodeToString(bytes)

		DB.Model(&ClusterConfig{}).Where("id = ?", "global").Update("api_token", newToken)
		os.Setenv("GBNT_API_TOKEN", newToken)

		// Print onboarding banner — this is the ONE-TIME output the operator must save.
		fmt.Println("")
		fmt.Println("╔══════════════════════════════════════════════════════════════════╗")
		fmt.Println("║          🏛  GUBERNATOR — FIRST BOOT CREDENTIALS                ║")
		fmt.Println("╠══════════════════════════════════════════════════════════════════╣")
		fmt.Printf( "║  API TOKEN  : %-51s ║\n", newToken)
		fmt.Println("║                                                                  ║")
		fmt.Println("║  Save this token! It will NOT be shown again.                   ║")
		fmt.Println("║  Use it to configure your remote gbnt CLI:                      ║")
		fmt.Println("║                                                                  ║")
		fmt.Println("║  gbnt config add-context myserver \\                             ║")
		fmt.Println("║      --server http://<MANAGER-IP>:4000 \\                        ║")
		fmt.Printf( "║      --token %-52s ║\n", newToken)
		fmt.Println("╚══════════════════════════════════════════════════════════════════╝")
		fmt.Println("")

		log.Println("Generated new API Token (see banner above).")
	}
}

// GetAPIToken returns the API Bearer token from the database.
func GetAPIToken() string {
	var config ClusterConfig
	if err := DB.First(&config, "id = ?", "global").Error; err != nil {
		return ""
	}
	return config.APIToken
}

// GetJoinToken returns the cluster join token from the database.
func GetJoinToken() string {
	var config ClusterConfig
	if err := DB.First(&config, "id = ?", "global").Error; err != nil {
		return ""
	}
	return config.JoinToken
}

// seedInitialData ensures that at least the local Manager node exists in the DB.
func seedInitialData() {
	var count int64
	DB.Model(&Node{}).Count(&count)

	if count == 0 {
		log.Println("Seeding initial Manager node into the database...")
		managerNode := Node{
			ID:     "node-local-manager",
			IP:     "127.0.0.1",
			Role:   "manager",
			Status: "active",
			Labels: map[string]string{
				"gbnt.node.role": "manager",
				"gbnt.node.zone": "local",
			},
		}

		if err := DB.Create(&managerNode).Error; err != nil {
			log.Printf("Failed to seed initial manager node: %v\n", err)
		} else {
			log.Println("Initial Manager node seeded successfully.")
		}
	}
}
