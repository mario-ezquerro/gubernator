package storage

import (
	"bytes"
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"
)

func TestCryptoStreamEncryptDecrypt(t *testing.T) {
	passphrase := "CorrectHorseBatteryStaple!2026#ENS"

	// 1. Test small payload (< 1 chunk)
	smallData := []byte("Hello, Gubernator Encrypted Storage! ENS RD 311/2022")
	var encBuf bytes.Buffer

	if err := EncryptStream(bytes.NewReader(smallData), &encBuf, passphrase); err != nil {
		t.Fatalf("EncryptStream failed: %v", err)
	}

	var decBuf bytes.Buffer
	if err := DecryptStream(bytes.NewReader(encBuf.Bytes()), &decBuf, passphrase); err != nil {
		t.Fatalf("DecryptStream failed: %v", err)
	}

	if !bytes.Equal(smallData, decBuf.Bytes()) {
		t.Fatalf("Decrypted data does not match original! got %q, want %q", decBuf.Bytes(), smallData)
	}

	// 2. Test multi-chunk payload (e.g. 200 KB > 3 chunks of 64KB)
	largeData := make([]byte, 200*1024)
	if _, err := rand.Read(largeData); err != nil {
		t.Fatalf("rand.Read failed: %v", err)
	}

	encBuf.Reset()
	if err := EncryptStream(bytes.NewReader(largeData), &encBuf, passphrase); err != nil {
		t.Fatalf("EncryptStream on large data failed: %v", err)
	}

	decBuf.Reset()
	if err := DecryptStream(bytes.NewReader(encBuf.Bytes()), &decBuf, passphrase); err != nil {
		t.Fatalf("DecryptStream on large data failed: %v", err)
	}

	if !bytes.Equal(largeData, decBuf.Bytes()) {
		t.Fatalf("Decrypted large data does not match original (size: %d vs %d)", decBuf.Len(), len(largeData))
	}
}

func TestCryptoWrongPassphrase(t *testing.T) {
	original := []byte("Top secret database credentials and keys")
	var encBuf bytes.Buffer

	if err := EncryptStream(bytes.NewReader(original), &encBuf, "ValidPassword123!"); err != nil {
		t.Fatalf("EncryptStream failed: %v", err)
	}

	var decBuf bytes.Buffer
	err := DecryptStream(bytes.NewReader(encBuf.Bytes()), &decBuf, "WrongPassword999!")
	if err == nil {
		t.Fatalf("expected DecryptStream to fail with wrong password, but succeeded!")
	}
	if err != ErrInvalidPassphrase {
		t.Logf("got expected error on wrong password: %v", err)
	}
}

func TestCryptoTamperedCiphertext(t *testing.T) {
	original := []byte("Database state to be tampered with")
	var encBuf bytes.Buffer

	if err := EncryptStream(bytes.NewReader(original), &encBuf, "PasswordForTamperTest123!"); err != nil {
		t.Fatalf("EncryptStream failed: %v", err)
	}

	raw := encBuf.Bytes()
	// Flip a bit in the ciphertext portion (after header + salt + nonce = 8 + 32 + 12 + 4 = 56)
	if len(raw) > 60 {
		raw[58] ^= 0xFF
	}

	var decBuf bytes.Buffer
	err := DecryptStream(bytes.NewReader(raw), &decBuf, "PasswordForTamperTest123!")
	if err == nil {
		t.Fatalf("expected DecryptStream to fail on tampered data, but succeeded!")
	}
}

func TestIsEncryptedArchive(t *testing.T) {
	tempDir := t.TempDir()
	encFile := filepath.Join(tempDir, "test.tar.gz.enc")
	plainFile := filepath.Join(tempDir, "test.tar.gz")

	// Write encrypted file
	f, err := os.Create(encFile)
	if err != nil {
		t.Fatalf("failed to create encFile: %v", err)
	}
	_ = EncryptStream(bytes.NewReader([]byte("encrypted data")), f, "password123")
	f.Close()

	// Write unencrypted plain file
	_ = os.WriteFile(plainFile, []byte("regular plain gzip/tar content"), 0644)

	isEnc, err := IsEncryptedArchive(encFile)
	if err != nil || !isEnc {
		t.Fatalf("expected encFile to be identified as encrypted, got isEnc=%v, err=%v", isEnc, err)
	}

	isPlain, err := IsEncryptedArchive(plainFile)
	if err != nil || isPlain {
		t.Fatalf("expected plainFile to NOT be identified as encrypted, got isPlain=%v, err=%v", isPlain, err)
	}
}
