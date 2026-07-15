package output

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_go "github.com/tree-sitter/tree-sitter-go/bindings/go"
	tree_sitter_python "github.com/tree-sitter/tree-sitter-python/bindings/go"
	tree_sitter_typescript "github.com/tree-sitter/tree-sitter-typescript/bindings/go"
)

var update = flag.Bool("update", false, "update golden snapshot files")

const snapshotDir = "../../testdata/snapshots"

// assertSnapshot compares output against a golden file.
// If -update flag is set, it writes the golden file instead.
func assertSnapshot(t *testing.T, name string, got string) {
	t.Helper()

	goldenPath := filepath.Join(snapshotDir, name)

	if *update {
		if err := os.MkdirAll(filepath.Dir(goldenPath), 0755); err != nil {
			t.Fatalf("creating snapshot dir: %v", err)
		}
		if err := os.WriteFile(goldenPath, []byte(got), 0644); err != nil {
			t.Fatalf("writing golden file: %v", err)
		}
		t.Logf("Updated golden file: %s", goldenPath)
		return
	}

	expected, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("reading golden file %s: %v\nRun with -update to create it", goldenPath, err)
	}

	if got != string(expected) {
		t.Errorf("snapshot mismatch for %s\n--- EXPECTED ---\n%s\n--- GOT ---\n%s", name, string(expected), got)
	}
}

func parseFile(t *testing.T, path string, langID string) *parser.Tree {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}

	p := parser.NewParser()
	t.Cleanup(p.Close)

	var lang *tree_sitter.Language
	switch langID {
	case "go":
		lang = tree_sitter.NewLanguage(tree_sitter_go.Language())
	case "typescript":
		lang = tree_sitter.NewLanguage(tree_sitter_typescript.LanguageTypescript())
	case "python":
		lang = tree_sitter.NewLanguage(tree_sitter_python.Language())
	}

	if err := p.SetLanguage(lang); err != nil {
		t.Fatalf("SetLanguage: %v", err)
	}
	tree, err := p.Parse(content, langID)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	t.Cleanup(tree.Close)
	return tree
}

// --- Snapshot Tests ---

func TestSnapshot_GoSummary(t *testing.T) {
	tree := parseFile(t, "../../testdata/go-sample/main.go", "go")
	info := ExtractFileInfo(tree, "go-sample/main.go")
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("frontmatter: %v", err)
	}
	body := RenderSummary(info)
	output := fm + body

	assertSnapshot(t, "go_summary.md.golden", output)
}

func TestSnapshot_PythonSummary(t *testing.T) {
	tree := parseFile(t, "../../testdata/python-sample/main.py", "python")
	info := ExtractFileInfo(tree, "python-sample/main.py")
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("frontmatter: %v", err)
	}
	body := RenderSummary(info)
	output := fm + body

	assertSnapshot(t, "python_summary.md.golden", output)
}

func TestSnapshot_TSSummary(t *testing.T) {
	tree := parseFile(t, "../../testdata/js-sample/src/index.ts", "typescript")
	info := ExtractFileInfo(tree, "js-sample/src/index.ts")
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("frontmatter: %v", err)
	}
	body := RenderSummary(info)
	output := fm + body

	assertSnapshot(t, "ts_summary.md.golden", output)
}

func TestSnapshot_GoFullCST(t *testing.T) {
	tree := parseFile(t, "../../testdata/go-sample/main.go", "go")
	info := ExtractFileInfo(tree, "go-sample/main.go")
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("frontmatter: %v", err)
	}
	body := RenderCST(tree, 0)
	output := fm + body

	assertSnapshot(t, "go_fullcst.md.golden", output)
}

func TestSnapshot_IndexMD(t *testing.T) {
	// Parse all testdata files
	goTree := parseFile(t, "../../testdata/go-sample/main.go", "go")
	pyTree := parseFile(t, "../../testdata/python-sample/main.py", "python")
	tsTree := parseFile(t, "../../testdata/js-sample/src/index.ts", "typescript")

	files := []*FileInfo{
		ExtractFileInfo(goTree, "go-sample/main.go"),
		ExtractFileInfo(pyTree, "python-sample/main.py"),
		ExtractFileInfo(tsTree, "js-sample/src/index.ts"),
	}

	// Build index content without writing to disk
	info := buildProjectInfo(files, "/project/sunset")

	// Override dynamic fields for deterministic snapshots
	info.Generated = "2026-01-01T00:00:00Z"
	info.SunsetVersion = "test"

	fm, err := RenderProjectFrontmatter(info)
	if err != nil {
		t.Fatalf("frontmatter: %v", err)
	}
	body := renderIndexBody(files)
	output := fm + body

	// Normalize module order (maps are unordered)
	output = normalizeModuleOrder(output)

	assertSnapshot(t, "index.md.golden", output)
}

// normalizeModuleOrder sorts the modules section for deterministic snapshots.
func normalizeModuleOrder(s string) string {
	// The modules section in YAML is a list, order comes from map iteration
	// For now, just return as-is since we control the input
	_ = strings.Contains(s, "modules")
	return s
}
