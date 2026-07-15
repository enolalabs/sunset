# Contributing to Sunset

Thank you for considering contributing to Sunset! 🌅

## Getting Started

```bash
git clone https://github.com/enolalabs/sunset.git
cd sunset
make build
make test
```

## Adding a New Language

Adding a new language requires only **one file**. Here's how:

### 1. Create the language binding file

Create `internal/language/<language>.go`:

```go
package language

import (
    tree_sitter "github.com/tree-sitter/go-tree-sitter"
    grammar "github.com/tree-sitter/tree-sitter-<language>/bindings/go"
)

func init() {
    Register(&Language{
        Name:       "Rust",
        ID:         "rust",
        Extensions: []string{".rs"},
        Grammar:    tree_sitter.NewLanguage(grammar.Language()),
    })
}
```

### 2. Add the grammar dependency

```bash
go get github.com/tree-sitter/tree-sitter-<language>
```

### 3. Add docstring extraction (optional)

If the language has a specific documentation format, add a case to
`internal/docstring/extract.go`:

```go
case "rust":
    return extractRustDoc(node, source)
```

### 4. Add test data

Create `testdata/<lang>-sample/` with a representative source file.

### 5. Run tests

```bash
make test
make lint
```

## Project Structure

```
sunset/
├── cmd/sunset/         # CLI entry point
├── pkg/sunset/         # Public Go API
├── internal/
│   ├── language/       # Language registry (add new languages here)
│   ├── parser/         # tree-sitter wrapper
│   ├── docstring/      # Documentation comment extraction
│   ├── output/         # Markdown rendering (frontmatter, summary, CST)
│   ├── scanner/        # Directory walker + gitignore
│   ├── analyzer/       # Import resolution + dependency graph
│   ├── cache/          # SHA256 hash caching
│   └── engine/         # Orchestration engine
├── testdata/           # Sample source files for testing
└── .golangci.yml       # Linter configuration
```

## Code Guidelines

- Run `make lint` before committing
- Add tests for new functionality
- Use `Close()` for any objects wrapping C pointers
- Check all error returns (`errcheck` is enforced)
- Keep the public API in `pkg/sunset/` minimal

## Reporting Issues

Please include:
- Sunset version (`sunset version`)
- Go version (`go version`)
- Operating system
- Steps to reproduce
- Sample source file if possible
