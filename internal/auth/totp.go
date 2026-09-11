package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"math"
	"net/url"
	"strconv"
	"strings"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

// TOTPConfig holds configuration for RFC 6238 time-based one-time passwords.
type TOTPConfig struct {
	Issuer    string
	Period    uint
	Digits    int
	Algorithm string
}

// DefaultTOTPConfig provides standard 30-second 6-digit SHA-1 configuration.
var DefaultTOTPConfig = TOTPConfig{
	Issuer:    "Gubernator",
	Period:    30,
	Digits:    6,
	Algorithm: "SHA1",
}

// GenerateBase32Secret generates a cryptographically secure 20-byte (160-bit) Base32 secret.
func GenerateBase32Secret() (string, error) {
	bytes := make([]byte, 20)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("failed to generate random bytes for secret: %w", err)
	}
	secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(bytes)
	return secret, nil
}

// GenerateOTPAuthURI creates the standard otpauth:// URI for scanning with authenticator apps.
func GenerateOTPAuthURI(username, secret string) string {
	issuer := DefaultTOTPConfig.Issuer
	label := fmt.Sprintf("%s:%s", issuer, username)

	v := url.Values{}
	v.Set("secret", secret)
	v.Set("issuer", issuer)
	v.Set("algorithm", DefaultTOTPConfig.Algorithm)
	v.Set("digits", strconv.Itoa(DefaultTOTPConfig.Digits))
	v.Set("period", strconv.Itoa(int(DefaultTOTPConfig.Period)))

	return fmt.Sprintf("otpauth://totp/%s?%s", url.PathEscape(label), v.Encode())
}

// GenerateCode calculates the current TOTP code for a given secret at a specific timestamp.
func GenerateCode(secret string, t time.Time) (string, error) {
	cleanSecret := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(secret), " ", ""))
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(cleanSecret)
	if err != nil {
		// Try with standard padding if unpadded decode failed
		key, err = base32.StdEncoding.DecodeString(cleanSecret)
		if err != nil {
			return "", fmt.Errorf("invalid base32 secret: %w", err)
		}
	}

	counter := uint64(t.Unix()) / uint64(DefaultTOTPConfig.Period)
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, counter)

	mac := hmac.New(sha1.New, key)
	mac.Write(buf)
	h := mac.Sum(nil)

	offset := h[len(h)-1] & 0x0f
	truncated := binary.BigEndian.Uint32(h[offset:offset+4]) & 0x7fffffff
	codeNum := truncated % uint32(math.Pow10(DefaultTOTPConfig.Digits))

	format := fmt.Sprintf("%%0%dd", DefaultTOTPConfig.Digits)
	return fmt.Sprintf(format, codeNum), nil
}

// ValidateCode checks a user-provided 6-digit TOTP code against the secret,
// allowing a drift tolerance of +/- 1 time step (30 seconds before/after).
func ValidateCode(secret, userCode string) bool {
	cleanCode := strings.TrimSpace(userCode)
	if len(cleanCode) != DefaultTOTPConfig.Digits {
		return false
	}

	now := time.Now()
	steps := []int{0, -1, 1}

	for _, step := range steps {
		t := now.Add(time.Duration(step*int(DefaultTOTPConfig.Period)) * time.Second)
		expectedCode, err := GenerateCode(secret, t)
		if err != nil {
			continue
		}
		if subtle.ConstantTimeCompare([]byte(cleanCode), []byte(expectedCode)) == 1 {
			return true
		}
	}
	return false
}

// GenerateBackupCodes produces 8 cryptographically random alphanumeric backup recovery codes (e.g., "ABCD-1234").
func GenerateBackupCodes(count int) ([]string, error) {
	if count <= 0 {
		count = 8
	}
	charset := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ" // unambiguous characters
	codes := make([]string, count)

	for i := 0; i < count; i++ {
		bytes := make([]byte, 8)
		if _, err := rand.Read(bytes); err != nil {
			return nil, err
		}
		var sb strings.Builder
		for j := 0; j < 8; j++ {
			if j == 4 {
				sb.WriteByte('-')
			}
			idx := int(bytes[j]) % len(charset)
			sb.WriteByte(charset[idx])
		}
		codes[i] = sb.String()
	}
	return codes, nil
}

// GenerateQRCodePNG encodes the given content (e.g. otpauth:// URI) into a PNG byte slice.
func GenerateQRCodePNG(content string, size int) ([]byte, error) {
	if size <= 0 {
		size = 256
	}
	pngBytes, err := qrcode.Encode(content, qrcode.Medium, size)
	if err != nil {
		return nil, fmt.Errorf("failed to encode QR code: %w", err)
	}
	return pngBytes, nil
}

// GenerateQRCodeDataURI encodes content into a base64 Data URI ("data:image/png;base64,...")
// that can be embedded directly in an <img> tag or decoded in Flutter Web.
func GenerateQRCodeDataURI(content string, size int) (string, error) {
	pngBytes, err := GenerateQRCodePNG(content, size)
	if err != nil {
		return "", err
	}
	encoded := base64.StdEncoding.EncodeToString(pngBytes)
	return fmt.Sprintf("data:image/png;base64,%s", encoded), nil
}
