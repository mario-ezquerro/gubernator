package db

import (
	"crypto/rand"
	"encoding/hex"
	"log"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

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
