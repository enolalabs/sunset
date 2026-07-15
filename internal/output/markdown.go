package output

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/enolalabs/sunset/internal/parser"
)

// WriteFileMD renders a parsed file as Markdown and writes it to the output directory.
func WriteFileMD(tree *parser.Tree, filePath string, outputDir string, mode Mode, maxDepth int) error {
	info := ExtractFileInfo(tree, filePath)
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		return fmt.Errorf("rendering frontmatter for %s: %w", filePath, err)
	}
	var body string
	if mode == ModeFullCST {
		body = RenderCST(tree, maxDepth)
	} else {
		body = RenderSummary(info)
	}
	content := fm + body
	outPath := filepath.Join(outputDir, "files", SanitizePath(filePath)+".md")
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}
	return os.WriteFile(outPath, []byte(content), 0644)
}

// SanitizePath converts a file path to a safe filename.
func SanitizePath(path string) string {
	path = filepath.Clean(path)
	path = strings.ReplaceAll(path, string(filepath.Separator), "_")
	path = strings.TrimLeft(path, "._")
	return path
}
