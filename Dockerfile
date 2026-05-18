FROM golang:alpine AS builder

WORKDIR /app

# Install build dependencies for go-sqlite3 (CGO)
RUN apk update && apk upgrade --no-cache && apk add --no-cache gcc musl-dev

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary with CGO enabled
RUN CGO_ENABLED=1 GOOS=linux go build -o gbnt ./cmd/gbnt

FROM alpine:latest

WORKDIR /app

# Add certificates, timezone data, sqlite, and Docker CLI (needed for local executor)
RUN apk update && apk upgrade --no-cache && apk --no-cache add ca-certificates tzdata sqlite docker-cli

# Copy the pre-built binary
COPY --from=builder /app/gbnt .

# Healthcheck — polls the telemetry port every 30s using Alpine's built-in wget
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4002/health || exit 1

# Expose CLI (4000), Web UI (4001), and Telemetry/Swagger/Metrics (4002) ports
EXPOSE 4000
EXPOSE 4001
EXPOSE 4002

# The gbnt binary is the entrypoint
ENTRYPOINT ["/app/gbnt"]
