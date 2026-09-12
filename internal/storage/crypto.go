package storage

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"

	"golang.org/x/crypto/pbkdf2"
)

var (
	// MagicHeader identifies a Gubernator AES-256-GCM encrypted backup archive.
	MagicHeader = []byte("GBNTENC1")

	// SaltSize defines the cryptographic salt size (32 bytes / 256 bits).
	SaltSize = 32

	// NonceSize defines the standard AES-GCM nonce size (12 bytes / 96 bits).
	NonceSize = 12

	// PBKDF2Iterations defines the key derivation iteration count (CCN-STIC / NIST recommended >= 100,000).
	PBKDF2Iterations = 100000

	// KeySize defines the AES-256 key size (32 bytes).
	KeySize = 32

	// ChunkSize defines the plaintext chunk size for streaming GCM encryption (64 KB).
	ChunkSize = 64 * 1024

	// ErrInvalidMagic is returned when a file does not begin with the GBNTENC1 header.
	ErrInvalidMagic = errors.New("not an encrypted Gubernator backup (invalid magic header)")

	// ErrInvalidPassphrase is returned when decryption fails authentication.
	ErrInvalidPassphrase = errors.New("invalid encryption passphrase or corrupted backup archive (authentication failed)")
)

// deriveKey derives a 256-bit AES key from a passphrase and a salt using PBKDF2-HMAC-SHA256.
func deriveKey(passphrase string, salt []byte) []byte {
	return pbkdf2.Key([]byte(passphrase), salt, PBKDF2Iterations, KeySize, sha256.New)
}

// computeChunkNonce generates a unique 12-byte nonce for a specific chunk index
// by combining the 12-byte base nonce with the 64-bit chunk sequence number.
func computeChunkNonce(baseNonce []byte, chunkIndex uint64) []byte {
	nonce := make([]byte, NonceSize)
	copy(nonce, baseNonce)
	// XOR the chunk index into the final 8 bytes of the nonce
	var indexBytes [8]byte
	binary.BigEndian.PutUint64(indexBytes[:], chunkIndex)
	for i := 0; i < 8; i++ {
		nonce[4+i] ^= indexBytes[i]
	}
	return nonce
}

// chunkAAD returns additional authenticated data binding each chunk to its sequence number.
func chunkAAD(chunkIndex uint64) []byte {
	aad := make([]byte, 8)
	binary.BigEndian.PutUint64(aad, chunkIndex)
	return aad
}

// EncryptStream reads plaintext from r, encrypts it using AES-256-GCM with PBKDF2 key derivation,
// and writes the authenticated encrypted stream to w.
func EncryptStream(r io.Reader, w io.Writer, passphrase string) error {
	if passphrase == "" {
		return errors.New("encryption passphrase cannot be empty")
	}

	// 1. Generate random salt and base nonce
	salt := make([]byte, SaltSize)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return fmt.Errorf("failed to generate cryptographic salt: %w", err)
	}

	baseNonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(rand.Reader, baseNonce); err != nil {
		return fmt.Errorf("failed to generate cryptographic nonce: %w", err)
	}

	// 2. Write Magic Header + Salt + BaseNonce
	if _, err := w.Write(MagicHeader); err != nil {
		return fmt.Errorf("failed to write magic header: %w", err)
	}
	if _, err := w.Write(salt); err != nil {
		return fmt.Errorf("failed to write salt: %w", err)
	}
	if _, err := w.Write(baseNonce); err != nil {
		return fmt.Errorf("failed to write base nonce: %w", err)
	}

	// 3. Derive AES-256 key
	key := deriveKey(passphrase, salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return fmt.Errorf("failed to initialize AES cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return fmt.Errorf("failed to initialize GCM cipher: %w", err)
	}

	// 4. Stream and encrypt in chunks
	buf := make([]byte, ChunkSize)
	var chunkIndex uint64 = 0

	for {
		n, readErr := io.ReadFull(r, buf)
		if n > 0 {
			nonce := computeChunkNonce(baseNonce, chunkIndex)
			ciphertext := gcm.Seal(nil, nonce, buf[:n], chunkAAD(chunkIndex))

			// Write 4-byte length prefix (big endian)
			var lenBuf [4]byte
			binary.BigEndian.PutUint32(lenBuf[:], uint32(len(ciphertext)))
			if _, err := w.Write(lenBuf[:]); err != nil {
				return fmt.Errorf("failed to write chunk length: %w", err)
			}

			// Write encrypted chunk + GCM auth tag
			if _, err := w.Write(ciphertext); err != nil {
				return fmt.Errorf("failed to write ciphertext chunk: %w", err)
			}

			chunkIndex++
		}

		if readErr == io.EOF || readErr == io.ErrUnexpectedEOF {
			break
		}
		if readErr != nil {
			return fmt.Errorf("failed to read plaintext: %w", readErr)
		}
	}

	// 5. Write 4-byte zero length as EOF sentinel marker
	var eofMarker [4]byte
	if _, err := w.Write(eofMarker[:]); err != nil {
		return fmt.Errorf("failed to write EOF marker: %w", err)
	}

	return nil
}

// DecryptStream reads an authenticated encrypted stream from r, verifies its integrity,
// and writes the decrypted plaintext to w. Returns ErrInvalidPassphrase if the key is incorrect
// or the data has been modified.
func DecryptStream(r io.Reader, w io.Writer, passphrase string) error {
	if passphrase == "" {
		return errors.New("decryption passphrase cannot be empty")
	}

	// 1. Verify Magic Header
	header := make([]byte, len(MagicHeader))
	if _, err := io.ReadFull(r, header); err != nil {
		return fmt.Errorf("failed to read magic header: %w", err)
	}
	for i := range MagicHeader {
		if header[i] != MagicHeader[i] {
			return ErrInvalidMagic
		}
	}

	// 2. Read Salt and BaseNonce
	salt := make([]byte, SaltSize)
	if _, err := io.ReadFull(r, salt); err != nil {
		return fmt.Errorf("failed to read salt: %w", err)
	}

	baseNonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(r, baseNonce); err != nil {
		return fmt.Errorf("failed to read base nonce: %w", err)
	}

	// 3. Derive AES-256 key
	key := deriveKey(passphrase, salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return fmt.Errorf("failed to initialize AES cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return fmt.Errorf("failed to initialize GCM cipher: %w", err)
	}

	// 4. Stream and decrypt chunks
	var chunkIndex uint64 = 0
	for {
		var lenBuf [4]byte
		if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
			return fmt.Errorf("unexpected EOF reading chunk length: %w", err)
		}

		chunkLen := binary.BigEndian.Uint32(lenBuf[:])
		if chunkLen == 0 {
			// Clean EOF marker reached
			break
		}

		// Security: chunk length must not exceed maximum possible chunk + GCM tag
		if chunkLen > uint32(ChunkSize+64) {
			return ErrInvalidPassphrase
		}

		ciphertext := make([]byte, chunkLen)
		if _, err := io.ReadFull(r, ciphertext); err != nil {
			return fmt.Errorf("unexpected EOF reading ciphertext chunk: %w", err)
		}

		nonce := computeChunkNonce(baseNonce, chunkIndex)
		plaintext, err := gcm.Open(nil, nonce, ciphertext, chunkAAD(chunkIndex))
		if err != nil {
			return ErrInvalidPassphrase
		}

		if _, err := w.Write(plaintext); err != nil {
			return fmt.Errorf("failed to write decrypted plaintext: %w", err)
		}

		chunkIndex++
	}

	return nil
}

// IsEncryptedArchive checks if a file begins with the Gubernator encryption magic header.
func IsEncryptedArchive(filePath string) (bool, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return false, err
	}
	defer f.Close()

	header := make([]byte, len(MagicHeader))
	n, err := f.Read(header)
	if err != nil && err != io.EOF {
		return false, err
	}
	if n < len(MagicHeader) {
		return false, nil
	}

	for i := range MagicHeader {
		if header[i] != MagicHeader[i] {
			return false, nil
		}
	}
	return true, nil
}
