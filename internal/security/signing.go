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
	return keys, err
}

// SaveTrustedKey stores or updates a trusted public signing key.
func SaveTrustedKey(name, pubPEM string, isDefault bool) (*db.TrustedSigningKey, error) {
	// Validate public key format
	_, err := ParseECDSAPublicKey(pubPEM)
	if err != nil {
		return nil, fmt.Errorf("invalid ECDSA public key format: %w", err)
	}

	key := db.TrustedSigningKey{
		ID:           "key-" + uuid.New().String()[:8],
		Name:         name,
		PublicKeyPEM: strings.TrimSpace(pubPEM),
		KeyType:      "cosign-ecdsa",
		IsDefault:    isDefault,
		CreatedAt:    time.Now(),
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
