package docker

import (
	"testing"
)

func TestParseCreatedByInstruction(t *testing.T) {
	tests := []struct {
		input       string
		expectedIns string
		expectedArg string
	}{
		{
			input:       "/bin/sh -c #(nop)  CMD [\"postgres\"]",
			expectedIns: "CMD",
			expectedArg: "[\"postgres\"]",
		},
		{
			input:       "/bin/sh -c #(nop)  EXPOSE 5432",
			expectedIns: "EXPOSE",
			expectedArg: "5432",
		},
		{
			input:       "/bin/sh -c #(nop)  ENV PG_VERSION=16.2-1.pgdg120+1",
			expectedIns: "ENV",
			expectedArg: "PG_VERSION=16.2-1.pgdg120+1",
		},
		{
			input:       "/bin/sh -c #(nop) WORKDIR /app",
			expectedIns: "WORKDIR",
			expectedArg: "/app",
		},
		{
			input:       "/bin/sh -c apk add --no-cache curl ca-certificates",
			expectedIns: "RUN",
			expectedArg: "apk add --no-cache curl ca-certificates",
		},
		{
			input:       "ENTRYPOINT [\"docker-entrypoint.sh\"]",
			expectedIns: "ENTRYPOINT",
			expectedArg: "[\"docker-entrypoint.sh\"]",
		},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			ins, arg := parseCreatedByInstruction(tt.input)
			if ins != tt.expectedIns {
				t.Errorf("expected instruction %q, got %q", tt.expectedIns, ins)
			}
			if arg != tt.expectedArg {
				t.Errorf("expected arg %q, got %q", tt.expectedArg, arg)
			}
		})
	}
}

func TestParseSizeToBytes(t *testing.T) {
	tests := []struct {
		input    string
		expected int64
	}{
		{"0B", 0},
		{"512 B", 512},
		{"10 KB", 10 * 1024},
		{"45.2 MB", 47395635},
		{"1.5 GB", 1610612736},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			res := parseSizeToBytes(tt.input)
			// allow slight rounding tolerance for float conversions
			diff := res - tt.expected
			if diff < -100 || diff > 100 {
				t.Errorf("parseSizeToBytes(%q) = %d, expected around %d", tt.input, res, tt.expected)
			}
		})
	}
}

func TestFormatBytes(t *testing.T) {
	if s := formatBytes(1024); s != "1.0 KB" {
		t.Errorf("expected '1.0 KB', got %q", s)
	}
	if s := formatBytes(1024 * 1024 * 50); s != "50.0 MB" {
		t.Errorf("expected '50.0 MB', got %q", s)
	}
}
