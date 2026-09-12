package auth

import (
	"errors"
	"fmt"
	"strings"
	"unicode"
)

var (
	ErrPasswordTooShort     = errors.New("password does not meet minimum length requirement")
	ErrPasswordNoUpper      = errors.New("password must contain at least one uppercase letter (A-Z)")
	ErrPasswordNoLower      = errors.New("password must contain at least one lowercase letter (a-z)")
	ErrPasswordNoDigit      = errors.New("password must contain at least one numerical digit (0-9)")
	ErrPasswordNoSpecial    = errors.New("password must contain at least one special character (!@#$%^&*...)")
	ErrPasswordSameAsUser   = errors.New("password cannot match or contain the username")
	ErrPasswordTrivial      = errors.New("password is too common or easily guessable")
)

var commonTrivialPasswords = map[string]struct{}{
	"password":     {},
	"admin":        {},
	"administrator": {},
	"123456":       {},
	"12345678":     {},
	"123456789":    {},
	"1234567890":   {},
	"gubernator":   {},
	"qwerty":       {},
	"letmein":      {},
}

// ValidatePassword checks if a password complies with ENS op.acc.2 & CCN-STIC guidelines.
func ValidatePassword(password, username string, minLength int, requireComplexity bool) error {
	trimmed := strings.TrimSpace(password)
	if minLength <= 0 {
		minLength = 12 // ENS Medio/Alto default
	}

	if len(trimmed) < minLength {
		return fmt.Errorf("%w (minimum %d characters required by ENS policy)", ErrPasswordTooShort, minLength)
	}

	lowerUser := strings.ToLower(strings.TrimSpace(username))
	lowerPass := strings.ToLower(trimmed)

	if lowerUser != "" && (lowerPass == lowerUser || strings.Contains(lowerPass, lowerUser)) {
		return ErrPasswordSameAsUser
	}

	if _, found := commonTrivialPasswords[lowerPass]; found {
		return ErrPasswordTrivial
	}

	if !requireComplexity {
		return nil
	}

	var hasUpper, hasLower, hasDigit, hasSpecial bool
	for _, r := range trimmed {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		case unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasSpecial = true
		}
	}

	if !hasUpper {
		return ErrPasswordNoUpper
	}
	if !hasLower {
		return ErrPasswordNoLower
	}
	if !hasDigit {
		return ErrPasswordNoDigit
	}
	if !hasSpecial {
		return ErrPasswordNoSpecial
	}

	return nil
}
