# 🌅 Sunset

**Codebase Indexer** — Parse your source code into structured Markdown documentation using [tree-sitter](https://tree-sitter.github.io/tree-sitter/).

Sunset scans your project, extracts functions, types, imports, and docstrings, then generates a set of Markdown files with YAML frontmatter — ready for AI consumption, documentation, or codebase exploration.

## Features

- 🌳 **Tree-sitter powered** — Accurate parsing via concrete syntax trees (CST)
- 📝 **Markdown output** — YAML frontmatter + structured body per file
- 🔍 **Summary & Full CST** — Choose between function-level overview or full tree dump
- 📦 **Multi-language** — Go, JavaScript, TypeScript, Python out of the box
- ⚡ **Incremental** — SHA256 caching, only re-parse changed files (29x speedup)
- 🔗 **Dependency graph** — Import resolution with circular dependency detection
- 🚀 **Parallel** — Worker pool with configurable concurrency

## Install

Pre-built binaries for **v1.0.1** are published on the
[GitHub Releases](https://github.com/enolalabs/sunset/releases) page.  Each
archive is named `sunset_<version>_<os>_<arch>.<format>` and is accompanied by
a `checksums.txt` file listing every SHA-256 digest.

### v1.0.1 release targets

| OS | Arch | Archive | Verified on |
|---|---|---|---|
| Linux | amd64 | `sunset_1.0.1_linux_amd64.tar.gz` | `ubuntu-24.04` |
| Linux | arm64 | `sunset_1.0.1_linux_arm64.tar.gz` | `ubuntu-24.04-arm` |
| macOS | amd64 | `sunset_1.0.1_darwin_amd64.tar.gz` | `macos-15-intel` |
| macOS | arm64 | `sunset_1.0.1_darwin_arm64.tar.gz` | `macos-15` |
| Windows | amd64 | `sunset_1.0.1_windows_amd64.zip` | `windows-2025` |

> Targets are built and verified on the named GitHub Actions runner
> environments.  No minimum OS or libc compatibility is claimed.

### Install with checksum verification

Each snippet below downloads **only** its target archive plus `checksums.txt`,
selects the matching SHA-256 entry, verifies it, extracts the archive, and runs
`sunset version`.  The snippets default to the version-explicit `v1.0.1` URL;
override `SUNSET_BASE_URL` to point at a loopback server for native pre-tag
testing.

> **SHA-256 detects corruption and byte mismatches but does NOT authenticate
> the publisher.**  Signing and attestations remain future work.

#### Linux

<!-- snippet: docs/snippets/v1.0.1/install-linux.sh -->
```bash
#!/usr/bin/env bash
# install-linux.sh — Install sunset v1.0.1 on Linux (amd64 or arm64).
#
# Downloads ONLY the target archive plus checksums.txt, verifies the matching
# SHA-256 entry, extracts the archive, and runs `sunset version`.
#
# Defaults to the public v1.0.1 release URL.  Override the base URL for native
# pre-tag testing:
#
#   SUNSET_BASE_URL=http://127.0.0.1:8080 ./install-linux.sh [amd64|arm64]
#
# SHA-256 detects corruption and byte mismatches.  It does NOT authenticate
# the publisher; signing and attestations remain future work.
set -euo pipefail

VERSION="1.0.1"
BASE_URL="${SUNSET_BASE_URL:-https://github.com/enolalabs/sunset/releases/download/v${VERSION}}"
ARCH="${1:-$(uname -m)}"

case "$ARCH" in
    x86_64)         ARCH="amd64" ;;
    aarch64|arm64)  ARCH="arm64" ;;
    amd64|arm64)    ;;
    *)
        echo "install-linux: unsupported arch '$ARCH' (expected amd64 or arm64)" >&2
        exit 2
        ;;
esac

ARCHIVE="sunset_${VERSION}_linux_${ARCH}.tar.gz"
INSTALL_DIR="${SUNSET_INSTALL_DIR:-/usr/local/bin}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading $ARCHIVE and checksums.txt"
curl -fsSL -o "$WORK/$ARCHIVE"      "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "$WORK/checksums.txt" "${BASE_URL}/checksums.txt"

echo "==> Verifying SHA-256 (selecting the $ARCHIVE entry)"
( cd "$WORK" && grep -F "$ARCHIVE" checksums.txt | sha256sum --check - )

echo "==> Extracting and installing to $INSTALL_DIR"
tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
if [ -w "$INSTALL_DIR" ]; then
    mv "$WORK/sunset" "$INSTALL_DIR/sunset"
else
    sudo mv "$WORK/sunset" "$INSTALL_DIR/sunset"
fi

echo "==> Verifying install"
"$INSTALL_DIR/sunset" version
```
<!-- /snippet: docs/snippets/v1.0.1/install-linux.sh -->

#### macOS

<!-- snippet: docs/snippets/v1.0.1/install-macos.sh -->
```bash
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
```
<!-- /snippet: docs/snippets/v1.0.1/install-macos.sh -->

#### Windows

<!-- snippet: docs/snippets/v1.0.1/install-windows.ps1 -->
```powershell
# install-windows.ps1 — Install sunset v1.0.1 on Windows (amd64).
#
# Downloads ONLY the target archive plus checksums.txt, verifies the matching
# SHA-256 digest, extracts the archive, and runs `sunset version`.
#
# Defaults to the public v1.0.1 release URL.  Override the base URL for native
# pre-tag testing:
#
#   $env:SUNSET_BASE_URL = "http://127.0.0.1:8080"; .\install-windows.ps1
#
# SHA-256 detects corruption and byte mismatches.  It does NOT authenticate
# the publisher; signing and attestations remain future work.
$ErrorActionPreference = "Stop"

$Version    = "1.0.1"
$DefaultUrl = "https://github.com/enolalabs/sunset/releases/download/v$Version"
$BaseUrl    = if ($env:SUNSET_BASE_URL) { $env:SUNSET_BASE_URL } else { $DefaultUrl }
$Arch       = "amd64"

$Archive    = "sunset_${Version}_windows_${Arch}.zip"
$InstallDir = if ($env:SUNSET_INSTALL_DIR) { $env:SUNSET_INSTALL_DIR } else { "$env:LOCALAPPDATA\Programs\sunset" }

$Work = Join-Path $env:TEMP "sunset-install-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $Work -Force | Out-Null

try {
    Write-Host "==> Downloading $Archive and checksums.txt"
    Invoke-WebRequest -Uri "$BaseUrl/$Archive"      -OutFile "$Work\$Archive"      -UseBasicParsing
    Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile "$Work\checksums.txt" -UseBasicParsing

    Write-Host "==> Verifying SHA-256 (selecting the $Archive entry)"
    $line = Get-Content "$Work\checksums.txt" | Where-Object { $_ -like "*$Archive" }
    if (-not $line) { throw "no checksum entry for $Archive in checksums.txt" }
    $expected = ($line -split '\s+')[0].Trim()
    $actual   = (Get-FileHash -Algorithm SHA256 "$Work\$Archive").Hash
    if ($actual.ToLower() -ne $expected.ToLower()) {
        throw "checksum mismatch for $Archive (expected $expected, got $actual)"
    }

    Write-Host "==> Extracting and installing to $InstallDir"
    Expand-Archive -Path "$Work\$Archive" -DestinationPath $Work -Force
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Move-Item -Path "$Work\sunset.exe" -Destination "$InstallDir\sunset.exe" -Force

    Write-Host "==> Verifying install"
    & "$InstallDir\sunset.exe" version
}
finally {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
```
<!-- /snippet: docs/snippets/v1.0.1/install-windows.ps1 -->

### From source

```bash
go install github.com/enolalabs/sunset/cmd/sunset@latest
```

Import the library:

```go
import "github.com/enolalabs/sunset/pkg/sunset"
```

### Build locally

```bash
git clone https://github.com/enolalabs/sunset.git
cd sunset
make build
# Binary: bin/sunset
```

## Quick Start

```bash
# Parse current directory
sunset parse .

# Parse a specific project
sunset parse /path/to/project

# Full CST output
sunset parse . --detail full

# Exclude test files
sunset parse . --exclude "*_test.go,*.test.ts"

# Incremental update (only changed files)
sunset update

# List supported languages
sunset languages

# Clean generated files
sunset clean
```

## Output Structure

```
your-project/
└── .sunset/
    ├── output/
    │   ├── index.md              # Project overview
    │   └── files/
    │       ├── main.go.md         # Per-file documentation
    │       ├── handler_user.go.md
    │       └── utils_helper.py.md
    └── cache/
        └── cache.json             # File hashes for incremental updates
```

### Example: Per-file Markdown

```yaml
---
file: main.go
language: go
package: main
lines: 28
function_count: 2
type_count: 0
import_count: 3
tags:
  - has-functions
  - has-imports
---
```

```markdown
## Functions

### main
- **Signature**: `func main()`
- **Line**: 15-19
- **Doc**: main starts the HTTP server and registers routes.

### setupRouter
- **Signature**: `func setupRouter() *http.ServeMux`
- **Line**: 23-27
- **Doc**: setupRouter creates and configures the HTTP router.

## Imports

| Import | Line |
|---|---|
| fmt | 5 |
| net/http | 6 |
```

## CLI Reference

| Command | Description |
|---|---|
| `sunset parse <path>` | Parse files and generate Markdown |
| `sunset update [path]` | Incremental update (re-parse changed only) |
| `sunset languages` | List supported languages |
| `sunset version` | Show version |
| `sunset clean [path]` | Remove cache and output |

### Parse Flags

| Flag | Default | Description |
|---|---|---|
| `--output` | `<path>/.sunset/output` | Output directory |
| `--detail` | `summary` | `summary` or `full` (full CST) |
| `--exclude` | — | Comma-separated glob patterns |
| `--concurrency` | NumCPU | Max parallel parsers |
| `--max-depth` | 0 (unlimited) | Tree depth limit for full mode |
| `--no-cache` | false | Force full re-parse |
| `--quiet` | false | Suppress non-error output |

## Supported Languages

| Language | Extensions | Docstring Format |
|---|---|---|
| Go | `.go` | `// Comment` above declarations |
| JavaScript | `.js`, `.jsx` | `/** JSDoc */` |
| TypeScript | `.ts`, `.tsx` | `/** JSDoc */` |
| Python | `.py` | `"""docstring"""` inside body |

Adding a new language requires only **one file** — see [CONTRIBUTING.md](CONTRIBUTING.md).

## As a Go Library

```go
package main

import (
    "fmt"
    "github.com/enolalabs/sunset/pkg/sunset"
)

func main() {
    result, err := sunset.ParseFile("main.go")
    if err != nil {
        panic(err)
    }
    defer result.Close()

    root := result.Tree()
    fmt.Printf("Language: %s\n", result.Language)
    fmt.Printf("Root: %s (%d children)\n", root.Kind(), root.ChildCount())

    // Walk the tree
    sunset.Walk(root, func(n *sunset.Node) bool {
        if n.Kind() == "function_declaration" {
            fmt.Printf("Function at line %d\n", n.StartLine())
        }
        return true
    })
}
```

## Performance

### Real-world Benchmarks

Tested on popular open-source repositories (single run, `--no-cache`, default concurrency):

| Repository | Language | Files | Functions | Types | Duration | Files/sec | Output |
|---|---|---|---|---|---|---|---|
| [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) | Go | 12,615 | 104,925 | 18,165 | **70.4s** | 179 | 69 MB |
| [golang/go](https://github.com/golang/go) | Go | 10,302 | 89,294 | 17,999 | **57.3s** | 180 | 55 MB |
| [microsoft/vscode](https://github.com/microsoft/vscode) | TypeScript | 10,002 | 31,640 | 16,404 | **59.1s** | 169 | 44 MB |
| [facebook/react](https://github.com/facebook/react) | JS/TS | 4,345 | 12,885 | 535 | **9.3s** | 467 | 18 MB |
| [tensorflow/tensorflow](https://github.com/tensorflow/tensorflow) | Python/Go | 3,194 | 64,695 | 6,864 | **125.9s** | 25 | 25 MB |
| [django/django](https://github.com/django/django) | Python/JS | 2,945 | 31,928 | 10,951 | **6.2s** | 475 | 15 MB |

> **Total**: 43,403 files parsed · 335,367 functions extracted · 70,918 types · 226 MB of structured documentation

### Micro-benchmarks (50 files)

| Metric | Value |
|---|---|
| Full parse | ~20ms |
| Incremental (1 changed) | ~0.7ms (**29x faster**) |
| Memory per file | ~66KB |
| Walker: 5,800 nodes | ~1.1ms |

## Development

```bash
make test           # Run all tests with race detector
make lint           # Run golangci-lint
make bench          # Run benchmarks
make test-coverage  # Generate coverage report
make clean          # Remove build artifacts
```

## License

MIT
