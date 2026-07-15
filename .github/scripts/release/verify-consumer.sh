#!/usr/bin/env bash
#
# verify-consumer.sh — Verify that an external module can import and use
# the sunset public API at a specific tag.
#
# Usage: verify-consumer.sh <tag> <work-dir>
#
# Requires the caller to export GOCACHE, GOMODCACHE, GOBIN.
# Creates the external module below <work-dir> (OUTSIDE the sunset checkout).
# Uses GOPROXY=direct so Go fetches directly from VCS.
#
# Optional testing seam:
#   SUNSET_REPLACE=<path>  if set, adds a 'replace' directive pointing to
#                          <path>.  In CI this is unset; in tests it points
#                          to the local checkout.
#
# Exits zero WITHOUT stdout on success (diagnostics to stderr).
# Exits non-zero with diagnostics on stderr on failure.
#
set -uo pipefail

_usage() {
    echo "usage: verify-consumer.sh <tag> <work-dir>" >&2
    echo "  tag       the exact release tag (e.g. v1.0.1)" >&2
    echo "  work-dir  writable directory; the consumer module is created below it" >&2
    echo "" >&2
    echo "Required environment:" >&2
    echo "  GOCACHE, GOMODCACHE, GOBIN must be exported by the caller" >&2
    echo "" >&2
    echo "Optional environment:" >&2
    echo "  SUNSET_REPLACE=<path>  add a go.mod replace directive (for local testing)" >&2
}

_fail() {
    echo "verify-consumer: $*" >&2
}

if [[ $# -ne 2 ]]; then
    _usage
    exit 2
fi

TAG="$1"
WORK_DIR="$2"

# Validate required environment variables
for var in GOCACHE GOMODCACHE GOBIN; do
    if [[ -z "${!var:-}" ]]; then
        _fail "required environment variable not set: $var"
        exit 2
    fi
done

mkdir -p "$WORK_DIR" || { _fail "cannot create work-dir: $WORK_DIR"; exit 1; }

# Create consumer directory below work-dir (outside the checkout)
CONSUMER_DIR="$WORK_DIR/consumer-$$"
rm -rf "$CONSUMER_DIR"
mkdir -p "$CONSUMER_DIR" || { _fail "cannot create consumer dir: $CONSUMER_DIR"; exit 1; }

trap 'rm -rf "$CONSUMER_DIR"' EXIT

cd "$CONSUMER_DIR" || { _fail "cannot cd to consumer dir"; exit 1; }

# Initialize module — all go command output goes to stderr (not stdout)
if ! go mod init consumer.example.com/verify >&2 2>&1; then
    _fail "go mod init failed"
    exit 1
fi

# Match the Go version required by the sunset module
go mod edit -go=1.26.2 || { _fail "go mod edit -go failed"; exit 1; }

# Default GOPROXY to direct (fetch from VCS) unless caller already set it.
# CI sets GOPROXY=direct explicitly; local tests may use the default proxy
# for transitive dependencies when SUNSET_REPLACE is set.
: "${GOPROXY:=direct}"
export GOPROXY
export GOFLAGS=-mod=mod

# Add the dependency
if [[ -n "${SUNSET_REPLACE:-}" ]]; then
    # Testing seam: use a replace directive instead of fetching from VCS
    go mod edit -replace "github.com/enolalabs/sunset=${SUNSET_REPLACE}" || {
        _fail "go mod edit -replace failed"
        exit 1
    }
    go mod edit -require "github.com/enolalabs/sunset@${TAG}" || {
        _fail "go mod edit -require failed"
        exit 1
    }
    # With a replace, go mod tidy downloads the local dependencies
    if ! go mod tidy >&2 2>&1; then
        _fail "go mod tidy failed"
        exit 1
    fi
else
    if ! go get "github.com/enolalabs/sunset@${TAG}" >&2 2>&1; then
        _fail "go get github.com/enolalabs/sunset@${TAG} failed"
        exit 1
    fi
fi

# Write the consumer program
cat > main.go <<'GOEOF'
package main

import (
	"fmt"
	"os"

	"github.com/enolalabs/sunset/pkg/sunset"
)

func main() {
	langs := sunset.Languages()
	want := map[string]bool{
		"go":         false,
		"javascript": false,
		"typescript": false,
		"python":     false,
	}
	for _, l := range langs {
		if _, ok := want[l.ID]; ok {
			want[l.ID] = true
		}
	}
	missing := []string{}
	for id, found := range want {
		if !found {
			missing = append(missing, id)
		}
	}
	if len(missing) > 0 {
		fmt.Fprintf(os.Stderr, "missing languages: %v\n", missing)
		os.Exit(1)
	}
}
GOEOF

# Compile and run — output to stderr, not stdout
if ! go build -o /dev/null ./... >&2 2>&1; then
    _fail "go build failed (compile mismatch)"
    exit 1
fi

if ! go run main.go >&2 2>&1; then
    _fail "consumer program failed (language mismatch)"
    exit 1
fi

exit 0
