.PHONY: build release test test-coverage bench lint clean install

BINARY_NAME=sunset
BUILD_DIR=bin
GOFLAGS=-trimpath
VERSION?=$(shell git describe --tags --abbrev=0 2>/dev/null)
LDFLAGS=-s -w
RELEASE_LDFLAGS=$(LDFLAGS) -X github.com/enolalabs/sunset/internal/version.BuildVersion=$(VERSION)

## build: Build the binary
build:
	@mkdir -p $(BUILD_DIR)
	go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/sunset/

## release: Build with the release version injected via ldflags (local untagged builds report dev)
release:
	@test -n "$(VERSION)" || (echo "ERROR: no git tag found; untagged builds report 'dev'" && exit 1)
	@mkdir -p $(BUILD_DIR)
	go build $(GOFLAGS) -ldflags "$(RELEASE_LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/sunset/

## test: Run all tests
test:
	go test ./... -v -race

## test-coverage: Run tests with coverage report
test-coverage:
	go test ./... -coverprofile=coverage.out -covermode=atomic
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

## bench: Run benchmarks
bench:
	go test ./... -bench=. -benchmem

## lint: Run linter
lint:
	golangci-lint run ./...

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR) coverage.out coverage.html .sunset/

## install: Install binary to GOPATH/bin
install:
	go install $(GOFLAGS) -ldflags "$(LDFLAGS)" ./cmd/sunset/

## help: Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## //' | column -t -s ':'
