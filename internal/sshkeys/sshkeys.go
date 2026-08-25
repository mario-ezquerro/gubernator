package sshkeys

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"golang.org/x/crypto/ssh"
)

const (
	SSHDir     = "/data/ssh"
	PrivateKey = "id_ed25519"
	PublicKey  = "id_ed25519.pub"
)

// EnsureSSHKeys generates an ED25519 SSH key pair in /data/ssh/ if it doesn't exist.
// This key is used by the Manager to SSH into worker nodes for Shell, Reboot, etc.
func EnsureSSHKeys() error {
	privPath := filepath.Join(SSHDir, PrivateKey)
	pubPath := filepath.Join(SSHDir, PublicKey)

	// If both already exist, nothing to do
	if _, err := os.Stat(privPath); err == nil {
		if _, err := os.Stat(pubPath); err == nil {
			slog.Info("SSH keys already exist", "path", SSHDir)
			return nil
		}
	}

	// Create directory
	if err := os.MkdirAll(SSHDir, 0700); err != nil {
		return fmt.Errorf("failed to create SSH directory %s: %w", SSHDir, err)
	}

	// Generate ED25519 key pair
	pubKey, privKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return fmt.Errorf("failed to generate ED25519 key: %w", err)
	}

	// Marshal private key to PEM (OpenSSH format)
	privBytes, err := ssh.MarshalPrivateKey(privKey, "gubernator-manager")
	if err != nil {
		return fmt.Errorf("failed to marshal private key: %w", err)
	}

	if writePrivErr := os.WriteFile(privPath, pem.EncodeToMemory(privBytes), 0600); writePrivErr != nil {
		return fmt.Errorf("failed to write private key: %w", writePrivErr)
	}

	// Marshal public key to authorized_keys format
	sshPub, err := ssh.NewPublicKey(pubKey)
	if err != nil {
		return fmt.Errorf("failed to create SSH public key: %w", err)
	}
	pubKeyStr := string(ssh.MarshalAuthorizedKey(sshPub))

	if writePubErr := os.WriteFile(pubPath, []byte(pubKeyStr), 0644); writePubErr != nil {
		return fmt.Errorf("failed to write public key: %w", writePubErr)
	}

	slog.Info("SSH keys generated successfully", "path", SSHDir)
	fmt.Println("🔑 SSH Key Pair generated for Manager → Worker connections:")
	fmt.Printf("   Private: %s\n", privPath)
	fmt.Printf("   Public:  %s\n", pubPath)

	return nil
}

// GetPublicKey returns the Manager's SSH public key string (authorized_keys format).
func GetPublicKey() (string, error) {
	pubPath := filepath.Join(SSHDir, PublicKey)
	data, err := os.ReadFile(pubPath)
	if err != nil {
		return "", fmt.Errorf("SSH public key not found at %s: %w", pubPath, err)
	}
	return string(data), nil
}
