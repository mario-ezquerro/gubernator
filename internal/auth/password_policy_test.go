package auth

import (
	"errors"
	"testing"
)

func TestValidatePassword(t *testing.T) {
	tests := []struct {
		name              string
		password          string
		username          string
		minLength         int
		requireComplexity bool
		wantErr           error
	}{
		{
			name:              "valid compliant ENS password",
			password:          "Imperium#Romanum2026!",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           nil,
		},
		{
			name:              "too short",
			password:          "Pass#123",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordTooShort,
		},
		{
			name:              "missing uppercase",
			password:          "imperium#romanum2026!",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordNoUpper,
		},
		{
			name:              "missing lowercase",
			password:          "IMPERIUM#ROMANUM2026!",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordNoLower,
		},
		{
			name:              "missing digit",
			password:          "Imperium#RomanumSpecial!",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordNoDigit,
		},
		{
			name:              "missing special symbol",
			password:          "ImperiumRomanum2026Year",
			username:          "centurion",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordNoSpecial,
		},
		{
			name:              "contains username",
			password:          "Admin#2026SecureKey!",
			username:          "admin",
			minLength:         12,
			requireComplexity: true,
			wantErr:           ErrPasswordSameAsUser,
		},
		{
			name:              "trivial password",
			password:          "gubernator",
			username:          "mario",
			minLength:         8,
			requireComplexity: false,
			wantErr:           ErrPasswordTrivial,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePassword(tt.password, tt.username, tt.minLength, tt.requireComplexity)
			if tt.wantErr != nil {
				if err == nil {
					t.Fatalf("expected error containing %v, got nil", tt.wantErr)
				}
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("expected error %v, got %v", tt.wantErr, err)
				}
			} else if err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
		})
	}
}
