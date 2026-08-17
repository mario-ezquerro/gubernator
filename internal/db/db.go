package db

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net"
	"os"
	"runtime"

	"github.com/glebarez/sqlite"
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
func Init(dbPath string) error {
	var err error
	DB, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		// Warn level: only logs slow queries and errors — keeps startup output clean
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}

	slog.Info("database connection established")

	err = DB.AutoMigrate(&Node{}, &ClusterConfig{}, &Stack{}, &Service{}, &Task{}, &CustomDNSRecord{}, &SLONotificationConfig{}, &LDAPConfig{})
	if err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}

	seedInitialData()
	return ensureClusterConfig()
}

// ensureClusterConfig atomically creates or loads both the join token and API token
// in a single pass. This avoids the two-phase bug where ensureJoinToken would create
// the DB row (without api_token), then ensureAPIToken couldn't distinguish "first boot"
// from "token already set" on a fresh volume.
//
// Priority for API token:
//  1. GBNT_API_TOKEN env var → persisted in DB (operator override)
//  2. token already in DB → loaded into env (survives restarts)
//  3. neither → generate + print first-boot banner (truly one-time)
func ensureClusterConfig() error {
	var config ClusterConfig
	firstBoot := false

	if err := DB.First(&config, "id = ?", "global").Error; err != nil {
		if err != gorm.ErrRecordNotFound {
			return fmt.Errorf("ensureClusterConfig: cannot read cluster config: %w", err)
		}

		// ── TRUE FIRST BOOT: row does not exist yet ──────────────────────
		firstBoot = true

		joinBytes := make([]byte, 16)
		if _, err := rand.Read(joinBytes); err != nil {
			return fmt.Errorf("generate join token: %w", err)
		}

		var apiToken string
		if env := os.Getenv("GBNT_API_TOKEN"); env != "" {
			apiToken = env // operator pre-set
			firstBoot = false // don't show banner when token is pre-set
		} else {
			apiBytes := make([]byte, 32)
			if _, err := rand.Read(apiBytes); err != nil {
				return fmt.Errorf("generate API token: %w", err)
			}
			apiToken = hex.EncodeToString(apiBytes)
		}

		config = ClusterConfig{
			ID:        "global",
			JoinToken: hex.EncodeToString(joinBytes),
			APIToken:  apiToken,
		}
		if err := DB.Create(&config).Error; err != nil {
			return fmt.Errorf("save cluster config: %w", err)
		}
		slog.Info("generated new cluster join token and API token")
	}

	// ── SUBSEQUENT BOOTS: row already exists ────────────────────────────────
	envToken := os.Getenv("GBNT_API_TOKEN")

	if envToken != "" && envToken != config.APIToken {
		// Operator changed the token via env var → update DB
		DB.Model(&ClusterConfig{}).Where("id = ?", "global").Update("api_token", envToken)
		config.APIToken = envToken
		slog.Info("API token updated from GBNT_API_TOKEN env var")
	} else if config.APIToken != "" && envToken == "" {
		// Load persisted token into env so the API middleware can read it
		os.Setenv("GBNT_API_TOKEN", config.APIToken)
		slog.Info("API token loaded from database")
	}

	// ── STARTUP & TOKEN INFO BANNER ─────────────────────────────────────────
	// Printed on EVERY startup so the token and its recovery instructions are always visible.
	newToken := config.APIToken
	os.Setenv("GBNT_API_TOKEN", newToken)

	fmt.Println("")
	fmt.Println("╔══════════════════════════════════════════════════════════════════════════════════╗")
	if firstBoot {
		fmt.Println("║            🏛  GUBERNATOR — PRIMER ARRANQUE / FIRST BOOT                        ║")
	} else {
		fmt.Println("║            🏛  GUBERNATOR — INICIALIZADO / SYSTEM STARTUP                        ║")
	}
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Println("║                                                                                  ║")
	if firstBoot {
		fmt.Println("║  Se han generado las credenciales del clúster.                                  ║")
		fmt.Println("║  Generated cluster credentials.                                                 ║")
	} else {
		fmt.Println("║  Credenciales del clúster cargadas correctamente de la base de datos.            ║")
		fmt.Println("║  Cluster credentials successfully loaded from the database.                     ║")
	}
	fmt.Println("║                                                                                  ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  🔑  API TOKEN (Bearer auth — REST API en puerto 4000)                          ║")
	fmt.Println("║      Este token identifica y autoriza todas las peticiones del CLI y API REST.  ║")
	fmt.Println("║      This token identifies and authorizes all CLI and REST API requests.         ║")
	fmt.Println("║                                                                                  ║")
	fmt.Printf( "║  ▶   %-76s  ◀  ║\n", newToken)
	fmt.Println("║                                                                                  ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  📋  QUÉ HACER AHORA / WHAT TO DO NEXT:                                        ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  1) Configura el CLI (local o en otro host):                                    ║")
	fmt.Println("║     (Configure the CLI — local or on a remote host)                             ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║     gbnt config add-context local \\                                             ║")
	fmt.Println("║         --server http://localhost:4000 \\                                        ║")
	fmt.Printf( "║         --token %-65s  ║\n", newToken)
	fmt.Println("║     gbnt config use-context local                                               ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  2) Si usas Docker, ejecuta comandos dentro del contenedor:                     ║")
	fmt.Println("║     (Or run CLI commands directly inside the container)                         ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║     docker exec -it gbnt-manager /app/gbnt node ls                              ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  3) Para añadir nodos worker al clúster o ver detalles del token:               ║")
	fmt.Println("║     (To join worker nodes or inspect cluster/token information)                 ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║     docker exec -it gbnt-manager /app/gbnt legion info                          ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║  4) Accede a los servicios web:                                                 ║")
	fmt.Println("║     Web UI       →  http://localhost:4001                                       ║")
	fmt.Println("║     Swagger/API  →  http://localhost:4002/swagger/index.html                    ║")
	fmt.Println("║     Health       →  http://localhost:4002/health                                ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Println("║  ℹ️  ¿CÓMO RECUPERAR ESTE TOKEN? / HOW TO RECOVER THIS TOKEN?                    ║")
	fmt.Println("║      Puedes recuperar el API Token y Join Token en cualquier momento            ║")
	fmt.Println("║      ejecutando el siguiente comando en el nodo manager:                         ║")
	fmt.Println("║      You can recover the API Token and Join Token at any time by running:        ║")
	fmt.Println("║                                                                                  ║")
	fmt.Println("║      docker exec -it gbnt-manager /app/gbnt legion info                          ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════════════════════════╝")
	fmt.Println("")
	return nil
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

// GetManagerIP returns the IP address of the cluster manager node.
func GetManagerIP() string {
	var manager Node
	if err := DB.First(&manager, "role = ?", "manager").Error; err == nil && manager.IP != "" {
		return manager.IP
	}
	return detectLocalIP()
}

// detectLocalIP returns the preferred outbound IP of this machine
// by opening a UDP connection (no data is sent) and reading the local address.
// If GBNT_HOST_IP is set, it will be prioritized.
func detectLocalIP() string {
	if envIP := os.Getenv("GBNT_HOST_IP"); envIP != "" {
		return envIP
	}

	conn, err := net.Dial("udp", "8.8.8.8:53")
	if err == nil {
		defer conn.Close()
		localAddr := conn.LocalAddr().(*net.UDPAddr)
		return localAddr.IP.String()
	}
	// Fallback to localhost if no connection
	return "127.0.0.1"
}

// seedInitialData ensures that at least the local Manager node exists in the DB.
func seedInitialData() {
	var count int64
	DB.Model(&Node{}).Count(&count)

	if count == 0 {
		slog.Info("seeding initial manager node")
		managerNode := Node{
			ID:     "node-local-manager",
			IP:     detectLocalIP(),
			Role:   "manager",
			Status: "active",
			Labels: map[string]string{
				"gbnt.node.role": "manager",
				"gbnt.node.zone": "local",
				"gbnt.node.arch": DetectArch(),
			},
		}

		if err := DB.Create(&managerNode).Error; err != nil {
			slog.Error("failed to seed initial manager node", "err", err)
		} else {
			slog.Info("initial manager node seeded")
		}
	} else {
		// Update the manager node with the real IP in case it was 127.0.0.1 or changed
		var managerNode Node
		if err := DB.First(&managerNode, "id = ?", "node-local-manager").Error; err == nil {
			currentIP := detectLocalIP()
			if managerNode.IP != currentIP {
				DB.Model(&managerNode).Update("ip", currentIP)
				slog.Info("updated manager node IP", "new_ip", currentIP)
			}
		}
	}
}

// DetectArch returns a standardized CPU architecture name.
func DetectArch() string {
	arch := runtime.GOARCH
	switch arch {
	case "amd64":
		return "x86_64"
	case "386":
		return "x86"
	case "arm64":
		return "arm64"
	case "arm":
		return "arm"
	default:
		return arch
	}
}

// UpdateNodeLabels saves new labels for a node, enforcing read-only system labels.
func UpdateNodeLabels(nodeID string, newLabels map[string]string) error {
	var node Node
	if err := DB.First(&node, "id = ?", nodeID).Error; err != nil {
		return err
	}

	if newLabels == nil {
		newLabels = make(map[string]string)
	}

	// Enforce role system label
	newLabels["gbnt.node.role"] = node.Role

	// Enforce CPU architecture system label (keep existing or detect if missing)
	archVal, exists := node.Labels["gbnt.node.arch"]
	if !exists || archVal == "" {
		archVal = DetectArch()
	}
	newLabels["gbnt.node.arch"] = archVal

	node.Labels = newLabels
	return DB.Save(&node).Error
}
