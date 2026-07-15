#!/usr/bin/env bash
# install-macos.sh — Install sunset v1.0.1 on macOS (amd64 or arm64).
#
# Downloads ONLY the target archive plus checksums.txt, verifies the matching
# SHA-256 entry, extracts the archive, and runs `sunset version`.
#
# Defaults to the public v1.0.1 release URL.  Override the base URL for native
# pre-tag testing:
#
#   SUNSET_BASE_URL=http://127.0.0.1:8080 ./install-macos.sh [amd64|arm64]
#
# SHA-256 detects corruption and byte mismatches.  It does NOT authenticate
# the publisher; signing and attestations remain future work.
set -euo pipefail

VERSION="1.0.1"
BASE_URL="${SUNSET_BASE_URL:-https://github.com/enolalabs/sunset/releases/download/v${VERSION}}"
ARCH="${1:-$(uname -m)}"

case "$ARCH" in
    x86_64)      ARCH="amd64" ;;
    arm64)       ARCH="arm64" ;;
    amd64|arm64) ;;
    *)
        echo "install-macos: unsupported arch '$ARCH' (expected amd64 or arm64)" >&2
        exit 2
        ;;
esac

ARCHIVE="sunset_${VERSION}_darwin_${ARCH}.tar.gz"
INSTALL_DIR="${SUNSET_INSTALL_DIR:-/usr/local/bin}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading $ARCHIVE and checksums.txt"
curl -fsSL -o "$WORK/$ARCHIVE"      "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "$WORK/checksums.txt" "${BASE_URL}/checksums.txt"

echo "==> Verifying SHA-256 (selecting the $ARCHIVE entry)"
( cd "$WORK" && grep -F "$ARCHIVE" checksums.txt | shasum -a 256 -c - )

echo "==> Extracting and installing to $INSTALL_DIR"
tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
if [ -w "$INSTALL_DIR" ]; then
    mv "$WORK/sunset" "$INSTALL_DIR/sunset"
else
    sudo mv "$WORK/sunset" "$INSTALL_DIR/sunset"
fi

echo "==> Verifying install"
"$INSTALL_DIR/sunset" version
