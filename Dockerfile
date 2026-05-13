FROM golang:alpine AS builder

WORKDIR /app

# Install build dependencies for go-sqlite3 (CGO)
RUN apk add --no-cache gcc musl-dev

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary with CGO enabled
RUN CGO_ENABLED=1 GOOS=linux go build -o gbnt ./cmd/gbnt

FROM alpine:latest

WORKDIR /app

# Add certificates and timezone data
RUN apk --no-cache add ca-certificates tzdata sqlite

# Copy the pre-built binary
COPY --from=builder /app/gbnt .

# Expose API and Metrics ports
EXPOSE 4000
EXPOSE 4001

# The gbnt binary is the entrypoint
ENTRYPOINT ["/app/gbnt"]
