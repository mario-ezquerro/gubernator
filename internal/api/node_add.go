package api

import (
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"golang.org/x/crypto/ssh"
)

type AddNodeRequest struct {
	Host     string `json:"host" binding:"required"`
	User     string `json:"user" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// detectLocalIP returns the preferred outbound IP of this machine
func detectLocalIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "127.0.0.1"
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP.String()
}

// @Summary Add Node via SSH
// @Description Provision a new worker node via SSH
// @Tags nodes
// @Accept json
// @Produce json
// @Param request body AddNodeRequest true "Node Credentials"
// @Success 200 {object} map[string]string
// @Router /v1/node/add [post]
func NodeAddHandler(c *gin.Context) {
	var req AddNodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	joinToken := db.GetJoinToken()
	apiToken := db.GetAPIToken()
	managerIP := detectLocalIP()

	config := &ssh.ClientConfig{
		User: req.User,
		Auth: []ssh.AuthMethod{
			ssh.Password(req.Password),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	addr := req.Host
	if !strings.Contains(addr, ":") {
		addr += ":22"
	}

	client, err := ssh.Dial("tcp", addr, config)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SSH connection failed: %v", err)})
		return
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to create SSH session: %v", err)})
		return
	}
	defer session.Close()

	script := fmt.Sprintf(`
		set -e
		if ! command -v docker > /dev/null; then
			curl -fsSL https://get.docker.com | sudo sh
		fi
		sudo docker rm -f gbnt-worker || true
		sudo docker run -d --name gbnt-worker \
			--network host \
			--restart unless-stopped \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-v /data:/data \
			marioezquerro/gubernator:latest \
			legion join --token %s --manager http://%s:4000 --api-token %s
	`, joinToken, managerIP, apiToken)

	out, err := session.CombinedOutput(script)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Provisioning script failed: %v\nOutput: %s", err, string(out))})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Node successfully provisioned and joining cluster."})
}
