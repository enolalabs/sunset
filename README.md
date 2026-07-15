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

### From source

```bash
go install github.com/enolalabs/sunset/cmd/sunset@latest
```

### From binary

Download from [GitHub Releases](https://github.com/enolalabs/sunset/releases):

| Platform | Architecture | File |
|---|---|---|
| Linux | x86_64 | `sunset_*_linux_amd64.tar.gz` |
| Linux | ARM64 | `sunset_*_linux_arm64.tar.gz` |
| macOS | Apple Silicon | `sunset_*_darwin_arm64.tar.gz` |

```bash
# Example: Linux amd64
curl -sL https://github.com/enolalabs/sunset/releases/latest/download/sunset_1.0.0_linux_amd64.tar.gz | tar xz
sudo mv sunset /usr/local/bin/
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
