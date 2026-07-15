// Package analyzer provides import extraction, resolution, and dependency graph analysis.
package analyzer

import (
	"github.com/enolalabs/sunset/internal/output"
)

// Import represents a resolved import.
type Import struct {
	Raw      string // original import string
	Resolved string // resolved file path (relative to root), empty if unresolved
	Status   ImportStatus
	Line     int
}

// ImportStatus indicates whether an import was resolved.
type ImportStatus string

const (
	StatusResolved   ImportStatus = "resolved"
	StatusExternal   ImportStatus = "external"
	StatusUnresolved ImportStatus = "unresolved"
)

// ExtractAndResolve extracts imports from a FileInfo and attempts to resolve them.
func ExtractAndResolve(info *output.FileInfo, projectFiles []string, rootDir string) []Import {
	var result []Import
	for _, imp := range info.Imports {
		resolved := Import{
			Raw:  imp.Path,
			Line: imp.Line,
		}

		// Try resolving
		target := resolveImport(imp.Path, info.Language, info.File, projectFiles, rootDir)
		if target != "" {
			resolved.Resolved = target
			resolved.Status = StatusResolved
		} else if isExternalImport(imp.Path, info.Language) {
			resolved.Status = StatusExternal
		} else {
			resolved.Status = StatusUnresolved
		}

		result = append(result, resolved)
	}
	return result
}
