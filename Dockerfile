FROM golang:alpine AS builder

WORKDIR /app

# Install build dependencies for go-sqlite3 (CGO)
RUN apk update && apk upgrade --no-cache && apk add --no-cache gcc musl-dev

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

ENV GOMAXPROCS=1
RUN CGO_ENABLED=1 GOMAXPROCS=1 GOOS=linux go build -p 1 -ldflags "-X main.version=${VERSION}" -o gbnt ./cmd/gbnt

FROM alpine:edge

WORKDIR /app

# Add /app to the system PATH so 'gbnt' can be executed from anywhere
ENV PATH="/app:${PATH}"

# Data directory for SQLite DB and persistent state
# Mount a Docker volume here to survive container restarts:
#   docker run -v gubernator-data:/data gubernator serve
ENV GBNT_DATA_DIR="/data"

# Add certificates, timezone data, sqlite, and Docker CLI (needed for local executor)
RUN apk update && apk upgrade --no-cache && apk --no-cache add ca-certificates tzdata sqlite docker-cli openssh-client

# Copy the pre-built binary & VERSION file
COPY --from=builder /app/gbnt .
COPY --from=builder /app/VERSION .

# Declare /data as a volume so Docker manages persistence automatically
# This ensures gubernator.db (tokens, nodes, stacks) survives restarts
VOLUME ["/data"]

# Healthcheck — polls the telemetry port every 30s using our native CLI
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/app/gbnt", "health"]

# Expose CLI (4000), Web UI (4001), and Telemetry/Swagger/Metrics (4002) ports
EXPOSE 4000
EXPOSE 4001
EXPOSE 4002

# The gbnt binary is the entrypoint
ENTRYPOINT ["/app/gbnt"]
