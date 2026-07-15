// Package scanner provides directory walking and file discovery for supported languages.
package scanner

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/enolalabs/sunset/internal/language"
)

// defaultSkipDirs are directories always skipped during scanning.
var defaultSkipDirs = map[string]bool{
	".git":         true,
	".idea":        true,
	".vscode":      true,
	"node_modules": true,
	"__pycache__":  true,
	"vendor":       true,
}

// Options configures the scanner behavior.
type Options struct {
	// ExcludePatterns are glob patterns to exclude (e.g., "*_test.go").
	ExcludePatterns []string

	// SkipGitignore disables .gitignore parsing.
	SkipGitignore bool
}

// Result holds the list of discovered files.
type Result struct {
	Files []string
	Root  string
}

// Scan recursively walks root and returns all supported source files.
func Scan(root string, opts *Options) (*Result, error) {
	if opts == nil {
		opts = &Options{}
	}

	root, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}

	// Load gitignore rules
	var gitignore *GitignoreRules
	if !opts.SkipGitignore {
		gitignore = LoadGitignore(root)
	}

	result := &Result{Root: root}

	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil // skip unreadable entries
		}

		name := d.Name()

		// Skip default directories
		if d.IsDir() {
			if defaultSkipDirs[name] {
				return filepath.SkipDir
			}
			// Skip hidden directories (starting with .)
			if len(name) > 1 && name[0] == '.' {
				return filepath.SkipDir
			}
			return nil
		}

		// Get path relative to root
		relPath, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}

		// Apply gitignore
		if gitignore != nil && gitignore.IsIgnored(relPath) {
			return nil
		}

		// Apply exclude patterns
		if isExcluded(relPath, name, opts.ExcludePatterns) {
			return nil
		}

		// Check if file extension is supported
		if language.IsSupported(name) {
			result.Files = append(result.Files, relPath)
		}

		return nil
	})

	return result, err
}

// isExcluded checks if a file matches any exclude pattern.
func isExcluded(relPath string, name string, patterns []string) bool {
	for _, pattern := range patterns {
		// Try matching against filename
		if matched, _ := filepath.Match(pattern, name); matched {
			return true
		}
		// Try matching against relative path
		if matched, _ := filepath.Match(pattern, relPath); matched {
			return true
		}
		// Try simple suffix match for patterns like "*.test.ts"
		if strings.HasPrefix(pattern, "*") {
			suffix := pattern[1:]
			if strings.HasSuffix(name, suffix) {
				return true
			}
		}
	}
	return false
}
