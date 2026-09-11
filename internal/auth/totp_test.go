package auth

import (
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

	// Validate code generated 25s ago (within 30s drift)
	pastCode, err := GenerateCode(secret, now.Add(-25*time.Second))
	if err == nil {
		if !ValidateCode(secret, pastCode) {
			t.Errorf("expected past drift code %s to be valid", pastCode)
		}
	}

	// Validate incorrect code
	if ValidateCode(secret, "000000") && code != "000000" {
		t.Error("expected 000000 to be invalid")
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
