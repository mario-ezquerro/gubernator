BINARY  := gbnt
VERSION := $(shell cat VERSION)
LDFLAGS := -ldflags "-X main.version=$(VERSION)"

.PHONY: all build test lint swagger docker clean

all: build

## build: compile the binary for the current platform
build:
	go build $(LDFLAGS) -o $(BINARY) ./cmd/gbnt

## test: run all tests with the race detector
test:
	go test -race -v ./...

## lint: run golangci-lint (requires golangci-lint on PATH)
lint:
	golangci-lint run --timeout=5m

## swagger: regenerate Swagger docs (requires swag on PATH)
swagger:
	swag init -g cmd/gbnt/main.go -o docs

## docker: build and tag the Docker image for the current platform
docker:
	docker build -t marioezquerro/gubernator:$(VERSION) -t marioezquerro/gubernator:latest .

## clean: remove the compiled binary
clean:
	rm -f $(BINARY)

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/## //'
