FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o gbnt ./cmd/gbnt

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
