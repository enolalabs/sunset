// Package sunset provides a high-level API for parsing source code into
// concrete syntax trees. It wraps tree-sitter with a developer-friendly
// interface suitable for building code analysis tools.
//
// Basic usage:
//
//	result, err := sunset.ParseFile("main.go")
//	if err != nil {
//	    log.Fatal(err)
//	}
//	defer result.Close()
//
//	result.Tree.Walk(func(node *sunset.Node, depth int) bool {
//	    fmt.Println(node.Type())
//	    return true
//	})
package sunset

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/enolalabs/sunset/internal/language"
	"github.com/enolalabs/sunset/internal/parser"
)

// FileResult holds the result of parsing a single file.
type FileResult struct {
	// Path is the file path that was parsed.
	Path string

	// Language is the detected language name (e.g., "Go", "Python").
	Language string

	// LanguageID is the short language identifier (e.g., "go", "python").
	LanguageID string

	// Source is the raw source code bytes.
	Source []byte

	// Tree provides access to the concrete syntax tree.
	Tree *TreeWrapper

	// internal tree reference for cleanup
	internalTree *parser.Tree
}

// Close releases the underlying C resources.
// Must be called when done with the FileResult.
func (r *FileResult) Close() {
	if r.internalTree != nil {
		r.internalTree.Close()
		r.internalTree = nil
	}
}

// HasErrors returns true if the parsed tree contains syntax errors.
func (r *FileResult) HasErrors() bool {
	if r.internalTree == nil {
		return false
	}
	return r.internalTree.HasErrors()
}

// ParseFile parses a single source file and returns the analysis result.
// The language is auto-detected from the file extension.
// The caller must call Close() on the returned FileResult when done.
func ParseFile(path string, opts ...Option) (*FileResult, error) {
	cfg := defaultConfig()
	for _, opt := range opts {
		opt(cfg)
	}

	// Read file
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading file %s: %w", path, err)
	}

	// Detect or use forced language
	var lang *language.Language
	if cfg.ForceLanguage != "" {
		lang, err = language.Get(cfg.ForceLanguage)
	} else {
		lang, err = language.Detect(filepath.Base(path))
	}
	if err != nil {
		return nil, fmt.Errorf("detecting language for %s: %w", path, err)
	}

	// Parse
	p := parser.NewParser()
	defer p.Close()

	if err := p.SetLanguage(lang.Grammar); err != nil {
		return nil, fmt.Errorf("setting language: %w", err)
	}

	tree, err := p.Parse(content, lang.ID)
	if err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}

	return &FileResult{
		Path:         path,
		Language:     lang.Name,
		LanguageID:   lang.ID,
		Source:       content,
		Tree:         newTreeWrapper(tree),
		internalTree: tree,
	}, nil
}

// Languages returns all supported languages.
func Languages() []LanguageInfo {
	var result []LanguageInfo
	for _, lang := range language.All() {
		result = append(result, LanguageInfo{
			Name:       lang.Name,
			ID:         lang.ID,
			Extensions: lang.Extensions,
		})
	}
	return result
}

// LanguageInfo describes a supported language.
type LanguageInfo struct {
	Name       string
	ID         string
	Extensions []string
}
