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
