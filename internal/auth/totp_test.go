package auth

import (
	"encoding/base32"
	"strings"
	"testing"
	"time"
)

func TestTOTPGenerationAndValidation(t *testing.T) {
	secret, err := GenerateBase32Secret()
	if err != nil {
		t.Fatalf("GenerateBase32Secret failed: %v", err)
	}
	if len(secret) == 0 {
		t.Fatal("secret is empty")
	}

	uri := GenerateOTPAuthURI("admin", secret)
	if uri == "" || len(uri) < 30 {
		t.Fatalf("unexpected otpauth URI: %s", uri)
	}

	now := time.Now()
	code, err := GenerateCode(secret, now)
	if err != nil {
		t.Fatalf("GenerateCode failed: %v", err)
	}
	if len(code) != 6 {
		t.Fatalf("expected 6 digits, got %s", code)
	}

	// Validate valid code
	if !ValidateCode(secret, code) {
		t.Errorf("expected code %s to be valid", code)
	}

	// Validate code with spaces (as formatted in Google Authenticator "123 456")
	formattedCode := code[:3] + " " + code[3:]
	if !ValidateCode(secret, formattedCode) {
		t.Errorf("expected formatted code with space %s to be valid", formattedCode)
	}

	// Validate code with dash "123-456"
	dashCode := code[:3] + "-" + code[3:]
	if !ValidateCode(secret, dashCode) {
		t.Errorf("expected dash code %s to be valid", dashCode)
	}

	// Validate code generated 70s ago (within 90s drift)
	driftCode, err := GenerateCode(secret, now.Add(-70*time.Second))
	if err == nil {
		if !ValidateCode(secret, driftCode) {
			t.Errorf("expected past drift code %s to be valid", driftCode)
		}
	}

	// Validate incorrect code
	// Validate RFC 6238 standard test vectors with key "12345678901234567890"
	// Base32 encoding of "12345678901234567890" is "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	rfcKey := "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	testVectors := []struct {
		timestamp int64
		expected  string
	}{
		{59, "287082"},
		{1111111109, "081804"},
		{1111111111, "050471"},
		{1234567890, "005924"},
		{2000000000, "279037"},
	}

	for _, tv := range testVectors {
		tVal := time.Unix(tv.timestamp, 0)
		c, err := GenerateCode(rfcKey, tVal)
		if err != nil {
			t.Fatalf("RFC test vector at %d failed: %v", tv.timestamp, err)
		}
		if c != tv.expected {
			t.Errorf("RFC test vector at %d: got %s, want %s", tv.timestamp, c, tv.expected)
		}
	}
}

func TestBackupCodes(t *testing.T) {
	codes, err := GenerateBackupCodes(8)
	if err != nil {
		t.Fatalf("GenerateBackupCodes failed: %v", err)
	}
	if len(codes) != 8 {
		t.Fatalf("expected 8 codes, got %d", len(codes))
	}
	for _, c := range codes {
		if len(c) != 9 || c[4] != '-' {
			t.Errorf("unexpected backup code format: %s", c)
		}
	}
}

func TestDecodeSecret(t *testing.T) {
	lengths := []int{10, 16, 20, 32}
	for _, l := range lengths {
		bytes := make([]byte, l)
		for i := 0; i < l; i++ {
			bytes[i] = byte(i + 1)
		}
		// Unpadded
		secNoPad := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(bytes)
		code1, err := GenerateCode(secNoPad, time.Now())
		if err != nil {
			t.Fatalf("GenerateCode failed for len %d unpadded: %v", l, err)
		}
		// Padded
		secPad := base32.StdEncoding.EncodeToString(bytes)
		code2, err := GenerateCode(secPad, time.Now())
		if err != nil {
			t.Fatalf("GenerateCode failed for len %d padded: %v", l, err)
		}
		if code1 != code2 {
			t.Errorf("len %d: code1 %s != code2 %s", l, code1, code2)
		}
		// Lowercase with spaces
		secMessy := "  " + strings.ToLower(secNoPad) + "  "
		code3, err := GenerateCode(secMessy, time.Now())
		if err != nil {
			t.Fatalf("GenerateCode failed for len %d messy: %v", l, err)
		}
		if code1 != code3 {
			t.Errorf("len %d: code1 %s != code3 %s", l, code1, code3)
		}
	}
}

func TestQRCodeGeneration(t *testing.T) {
	uri := "otpauth://totp/Gubernator:admin?secret=JBSWY3DPEHPK3PXP&issuer=Gubernator"
	pngBytes, err := GenerateQRCodePNG(uri, 256)
	if err != nil {
		t.Fatalf("GenerateQRCodePNG failed: %v", err)
	}
	if len(pngBytes) == 0 {
		t.Fatal("GenerateQRCodePNG returned empty byte slice")
	}
	// PNG magic header is 0x89 'P' 'N' 'G'
	if len(pngBytes) < 4 || pngBytes[0] != 0x89 || pngBytes[1] != 'P' || pngBytes[2] != 'N' || pngBytes[3] != 'G' {
		t.Fatalf("expected PNG header, got %v", pngBytes[:4])
	}

	dataURI, err := GenerateQRCodeDataURI(uri, 256)
	if err != nil {
		t.Fatalf("GenerateQRCodeDataURI failed: %v", err)
	}
	prefix := "data:image/png;base64,"
	if len(dataURI) <= len(prefix) || dataURI[:len(prefix)] != prefix {
		t.Fatalf("expected data URI to start with '%s', got '%s'", prefix, dataURI)
	}
}
