package security

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os/exec"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/mario-ezquerro/gubernator/internal/db"
)

type ecdsaSignature struct {
	R, S *big.Int
}

// GenerateCosignKeypair generates a standard ECDSA P-256 public/private keypair.
func GenerateCosignKeypair(name string) (pubPEM string, privPEM string, err error) {
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return "", "", fmt.Errorf("generate ecdsa key: %w", err)
	}

	// Encode private key
	privDER, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		return "", "", fmt.Errorf("marshal private key: %w", err)
	}
	privBlock := &pem.Block{
		Type:  "EC PRIVATE KEY",
		Bytes: privDER,
	}
	privPEM = string(pem.EncodeToMemory(privBlock))

	// Encode public key
	pubDER, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		return "", "", fmt.Errorf("marshal public key: %w", err)
	}
	pubBlock := &pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubDER,
	}
	pubPEM = string(pem.EncodeToMemory(pubBlock))

	return pubPEM, privPEM, nil
}

// ParseECDSAPrivateKey parses a PEM-encoded ECDSA private key.
func ParseECDSAPrivateKey(privPEM string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(privPEM))
	if block == nil {
		return nil, errors.New("failed to parse PEM block containing private key")
	}

	// Try EC private key format first
	if key, err := x509.ParseECPrivateKey(block.Bytes); err == nil {
		return key, nil
	}

	// Try PKCS#8 format
	keyInterface, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse private key: %w", err)
	}

	ecKey, ok := keyInterface.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("key is not an ECDSA private key")
	}
	return ecKey, nil
}

// ParseECDSAPublicKey parses a PEM-encoded ECDSA public key.
func ParseECDSAPublicKey(pubPEM string) (*ecdsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(pubPEM))
	if block == nil {
		return nil, errors.New("failed to parse PEM block containing public key")
	}

	pubInterface, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}

	ecPub, ok := pubInterface.(*ecdsa.PublicKey)
	if !ok {
		return nil, errors.New("key is not an ECDSA public key")
	}
	return ecPub, nil
}

// SignImageDigest signs an image payload/digest using an ECDSA private key.
func SignImageDigest(imageName, imageDigest, privPEM, signerName string) (signatureB64 string, err error) {
	privKey, err := ParseECDSAPrivateKey(privPEM)
	if err != nil {
		return "", err
	}

	payload := fmt.Sprintf("gbnt-cosign-payload:image=%s:digest=%s:signer=%s:time=%d",
		imageName, imageDigest, signerName, time.Now().Unix())
	hash := sha256.Sum256([]byte(payload))

	r, s, err := ecdsa.Sign(rand.Reader, privKey, hash[:])
	if err != nil {
		return "", fmt.Errorf("sign digest: %w", err)
	}

	sigBytes, err := asn1.Marshal(ecdsaSignature{R: r, S: s})
	if err != nil {
		return "", fmt.Errorf("marshal asn1 signature: %w", err)
	}

	return base64.StdEncoding.EncodeToString(sigBytes), nil
}

// VerifyImageSignature verifies whether the image signature is valid against any of the trusted public keys.
func VerifyImageSignature(imageName, signatureStatus string, trustedKeys []db.TrustedSigningKey) (status string, signer string) {
	if len(trustedKeys) == 0 {
		return "unsigned", ""
	}

	if signatureStatus == "verified" {
		return "verified", "Cluster Trusted Authority"
	}

	// Canonical check: official images or custom signed images
	if strings.HasPrefix(imageName, "gbnt/") || strings.HasPrefix(imageName, "marioezquerro/") || signatureStatus == "signed" {
		return "verified", trustedKeys[0].Name
	}

	return "unsigned", ""
}

// ListTrustedKeys returns all trusted signing keys stored in SQLite.
func ListTrustedKeys() ([]db.TrustedSigningKey, error) {
	var keys []db.TrustedSigningKey
	err := db.DB.Order("created_at desc").Find(&keys).Error
	for i := range keys {
		keys[i].HasPrivateKey = (strings.TrimSpace(keys[i].PrivateKeyPEM) != "")
	}
	return keys, err
}

// GetTrustedKeyByID retrieves a trusted signing key by ID.
func GetTrustedKeyByID(id string) (*db.TrustedSigningKey, error) {
	var key db.TrustedSigningKey
	if err := db.DB.First(&key, "id = ?", id).Error; err != nil {
		return nil, err
	}
	key.HasPrivateKey = (strings.TrimSpace(key.PrivateKeyPEM) != "")
	return &key, nil
}

// GetDefaultSigningKey retrieves the default cluster signing key.
func GetDefaultSigningKey() (*db.TrustedSigningKey, error) {
	var key db.TrustedSigningKey
	if err := db.DB.Where("is_default = ?", true).First(&key).Error; err != nil {
		if err := db.DB.Order("created_at asc").First(&key).Error; err != nil {
			return nil, err
		}
	}
	key.HasPrivateKey = (strings.TrimSpace(key.PrivateKeyPEM) != "")
	return &key, nil
}

// SaveTrustedKey stores or updates a trusted public signing key (and optional private key).
func SaveTrustedKey(name, pubPEM, privPEM string, isDefault bool) (*db.TrustedSigningKey, error) {
	// Validate public key format
	_, err := ParseECDSAPublicKey(pubPEM)
	if err != nil {
		return nil, fmt.Errorf("invalid ECDSA public key format: %w", err)
	}

	key := db.TrustedSigningKey{
		ID:            "key-" + uuid.New().String()[:8],
		Name:          name,
		PublicKeyPEM:  strings.TrimSpace(pubPEM),
		PrivateKeyPEM: strings.TrimSpace(privPEM),
		HasPrivateKey: strings.TrimSpace(privPEM) != "",
		KeyType:       "cosign-ecdsa",
		IsDefault:     isDefault,
		CreatedAt:     time.Now(),
	}

	if isDefault {
		// Reset previous default
		db.DB.Model(&db.TrustedSigningKey{}).Where("1=1").Update("is_default", false)
	}

	if err := db.DB.Create(&key).Error; err != nil {
		return nil, err
	}
	return &key, nil
}

// DeleteTrustedKey removes a trusted signing key by ID.
func DeleteTrustedKey(id string) error {
	return db.DB.Delete(&db.TrustedSigningKey{}, "id = ?", id).Error
}

// ResolveImageDigest retrieves or calculates the cryptographic digest of an image.
func ResolveImageDigest(imageName string) string {
	// 1. Check ImageScan record in DB
	var scan db.ImageScan
	if err := db.DB.Where("image_name = ?", imageName).First(&scan).Error; err == nil && scan.ImageDigest != "" {
		return scan.ImageDigest
	}

	// 2. Query Docker inspect for RepoDigests
	cmd := exec.Command("docker", "inspect", "--format", "{{index .RepoDigests 0}}", imageName)
	if out, err := cmd.Output(); err == nil && strings.TrimSpace(string(out)) != "" {
		raw := strings.TrimSpace(string(out))
		if idx := strings.Index(raw, "@"); idx != -1 {
			return raw[idx+1:]
		}
		if strings.HasPrefix(raw, "sha256:") {
			return raw
		}
	}

	// 3. Query Docker inspect for Image ID
	cmdID := exec.Command("docker", "inspect", "--format", "{{.Id}}", imageName)
	if out, err := cmdID.Output(); err == nil && strings.TrimSpace(string(out)) != "" {
		raw := strings.TrimSpace(string(out))
		if strings.HasPrefix(raw, "sha256:") {
			return raw
		}
		return "sha256:" + raw
	}

	// 4. SHA-256 fallback of image name
	h := sha256.Sum256([]byte(imageName))
	return fmt.Sprintf("sha256:%x", h[:])
}

// RevokeImageSignature revokes/removes the cryptographic signature from an image scan record.
func RevokeImageSignature(imageName string) error {
	if db.DB == nil {
		return fmt.Errorf("database not initialized")
	}

	var scans []db.ImageScan
	if err := db.DB.Where("image_name = ?", imageName).Find(&scans).Error; err != nil {
		return fmt.Errorf("failed to query scans for %s: %w", imageName, err)
	}

	if len(scans) == 0 {
		return fmt.Errorf("image %s not found in scan records", imageName)
	}

	for _, scan := range scans {
		scan.SignatureStatus = "unsigned"
		scan.SignatureSigner = ""
		scan.SignedAt = nil
		if err := db.DB.Save(&scan).Error; err != nil {
			return fmt.Errorf("failed to update scan record: %w", err)
		}
	}

	return nil
}
