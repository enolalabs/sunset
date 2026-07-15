package output

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/enolalabs/sunset/internal/version"
)

// WriteIndexMD generates the index.md file from a list of FileInfos.
func WriteIndexMD(files []*FileInfo, projectRoot string, outputDir string) error {
	info := buildProjectInfo(files, projectRoot)
	fm, err := RenderProjectFrontmatter(info)
	if err != nil {
		return fmt.Errorf("rendering project frontmatter: %w", err)
	}
	body := renderIndexBody(files)
	content := fm + body
	outPath := filepath.Join(outputDir, "index.md")
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}
	return os.WriteFile(outPath, []byte(content), 0644)
}

func buildProjectInfo(files []*FileInfo, root string) *ProjectInfo {
	info := &ProjectInfo{
		Project:       filepath.Base(root),
		Root:          root,
		Generated:     time.Now().Format(time.RFC3339),
		SunsetVersion: version.Current(),
		Languages:     make(map[string]LanguageStat),
		TotalFiles:    len(files),
	}
	for _, f := range files {
		stat := info.Languages[f.Language]
		stat.Files++
		info.Languages[f.Language] = stat
		info.TotalFunctions += f.FunctionCount
		info.TotalTypes += f.TypeCount
	}
	for lang, stat := range info.Languages {
		if info.TotalFiles > 0 {
			stat.Percentage = stat.Files * 100 / info.TotalFiles
		}
		info.Languages[lang] = stat
	}
	// Build modules (group by directory)
	modules := make(map[string]int)
	for _, f := range files {
		dir := filepath.Dir(f.File)
		modules[dir]++
	}
	for path, count := range modules {
		info.Modules = append(info.Modules, ModuleInfo{Path: path, Files: count})
	}
	sort.Slice(info.Modules, func(i, j int) bool {
		return info.Modules[i].Path < info.Modules[j].Path
	})
	return info
}

func renderIndexBody(files []*FileInfo) string {
	var b strings.Builder
	b.WriteString("\n## Files\n\n")
	b.WriteString("| File | Language | Functions | Types | Lines |\n")
	b.WriteString("|---|---|---|---|---|\n")
	for _, f := range files {
		b.WriteString(fmt.Sprintf("| %s | %s | %d | %d | %d |\n",
			f.File, f.Language, f.FunctionCount, f.TypeCount, f.Lines))
	}
	return b.String()
}
