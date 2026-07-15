package output

import (
	"os"
	"strings"
	"testing"

	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_go "github.com/tree-sitter/tree-sitter-go/bindings/go"
	tree_sitter_python "github.com/tree-sitter/tree-sitter-python/bindings/go"
	tree_sitter_typescript "github.com/tree-sitter/tree-sitter-typescript/bindings/go"

	"gopkg.in/yaml.v3"
)

func parseSource(t *testing.T, source string, langID string) *parser.Tree {
	t.Helper()
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
	tree, err := p.Parse([]byte(source), langID)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	t.Cleanup(tree.Close)
	return tree
}

// --- Frontmatter tests ---

func TestRenderFileFrontmatter_ValidYAML(t *testing.T) {
	info := &FileInfo{
		File:          "main.go",
		Language:      "go",
		Package:       "main",
		Lines:         50,
		FunctionCount: 3,
		TypeCount:     1,
		ImportCount:   2,
	}
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Should start and end with ---
	if !strings.HasPrefix(fm, "---\n") {
		t.Error("frontmatter should start with ---")
	}
	if !strings.HasSuffix(fm, "---\n") {
		t.Error("frontmatter should end with ---")
	}

	// Parse back as YAML
	yamlContent := strings.TrimPrefix(fm, "---\n")
	yamlContent = strings.TrimSuffix(yamlContent, "---\n")
	var parsed map[string]interface{}
	if err := yaml.Unmarshal([]byte(yamlContent), &parsed); err != nil {
		t.Fatalf("frontmatter is not valid YAML: %v", err)
	}

	if parsed["file"] != "main.go" {
		t.Errorf("expected file 'main.go', got %v", parsed["file"])
	}
	if parsed["language"] != "go" {
		t.Errorf("expected language 'go', got %v", parsed["language"])
	}
}

func TestRenderFileFrontmatter_Compact(t *testing.T) {
	info := &FileInfo{
		File:     "test.go",
		Language: "go",
		Tags:     make([]string, 20), // 20 tags
	}
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Tags should be limited to 10
	yamlContent := strings.TrimPrefix(fm, "---\n")
	yamlContent = strings.TrimSuffix(yamlContent, "---\n")
	var parsed struct {
		Tags []string `yaml:"tags"`
	}
	if err := yaml.Unmarshal([]byte(yamlContent), &parsed); err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(parsed.Tags) > 10 {
		t.Errorf("expected max 10 tags, got %d", len(parsed.Tags))
	}
}

func TestRenderFileFrontmatter_RequiredFields(t *testing.T) {
	info := &FileInfo{
		File:          "handler.go",
		Language:      "go",
		Lines:         100,
		FunctionCount: 5,
		TypeCount:     2,
	}
	fm, err := RenderFileFrontmatter(info)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	required := []string{"file:", "language:", "lines:", "function_count:", "type_count:"}
	for _, field := range required {
		if !strings.Contains(fm, field) {
			t.Errorf("frontmatter missing field %q", field)
		}
	}
}

// --- Summary tests ---

func TestExtractFileInfo_Go(t *testing.T) {
	source := `package main

import (
	"fmt"
	"net/http"
)

// Port is the default port.
const Port = "8080"

// Hello greets the world.
func Hello() string {
	return "hello"
}

func internal() {}
`
	tree := parseSource(t, source, "go")
	info := ExtractFileInfo(tree, "main.go")

	if info.Package != "main" {
		t.Errorf("expected package 'main', got %q", info.Package)
	}
	if info.FunctionCount != 2 {
		t.Errorf("expected 2 functions, got %d", info.FunctionCount)
	}
	if info.ImportCount != 2 {
		t.Errorf("expected 2 imports, got %d", info.ImportCount)
	}
	// Check exported function
	found := false
	for _, f := range info.Functions {
		if f.Name == "Hello" {
			found = true
			if !f.Exported {
				t.Error("Hello should be exported")
			}
			if f.Doc == "" {
				t.Error("Hello should have docstring")
			}
		}
	}
	if !found {
		t.Error("function Hello not found")
	}
}

func TestExtractFileInfo_Python(t *testing.T) {
	source := `"""Main module."""

from models.user import User

def create_user(name: str) -> User:
    """Create a new user."""
    return User(name=name)

class UserService:
    """Service for users."""
    def get(self, id):
        pass
`
	tree := parseSource(t, source, "python")
	info := ExtractFileInfo(tree, "main.py")

	if info.FunctionCount < 1 {
		t.Errorf("expected at least 1 function, got %d", info.FunctionCount)
	}
	if info.TypeCount < 1 {
		t.Errorf("expected at least 1 type (class), got %d", info.TypeCount)
	}
	if info.ImportCount < 1 {
		t.Errorf("expected at least 1 import, got %d", info.ImportCount)
	}
}

func TestExtractFileInfo_TypeScript(t *testing.T) {
	source := `import { helper } from './utils';

interface User {
  id: string;
  name: string;
}

type Role = 'admin' | 'user';

export function getUser(id: string): User {
  return { id, name: 'test' };
}
`
	tree := parseSource(t, source, "typescript")
	info := ExtractFileInfo(tree, "index.ts")

	if info.TypeCount < 2 {
		t.Errorf("expected at least 2 types (interface+alias), got %d", info.TypeCount)
	}
	if info.ImportCount < 1 {
		t.Errorf("expected at least 1 import, got %d", info.ImportCount)
	}
}

func TestRenderSummary_GoFile(t *testing.T) {
	source := `package main

import "fmt"

// Hello says hello.
func Hello(name string) string {
	return fmt.Sprintf("hello %s", name)
}

func goodbye() {}
`
	tree := parseSource(t, source, "go")
	info := ExtractFileInfo(tree, "main.go")
	summary := RenderSummary(info)

	if !strings.Contains(summary, "## Functions") {
		t.Error("summary should contain ## Functions section")
	}
	if !strings.Contains(summary, "Hello") {
		t.Error("summary should contain function Hello")
	}
	if !strings.Contains(summary, "goodbye") {
		t.Error("summary should contain function goodbye")
	}
	if !strings.Contains(summary, "## Imports") {
		t.Error("summary should contain ## Imports section")
	}
}

// --- CST tests ---

func TestRenderCST(t *testing.T) {
	source := "package main\n\nfunc main() {}\n"
	tree := parseSource(t, source, "go")
	cst := RenderCST(tree, 0)

	if !strings.Contains(cst, "source_file") {
		t.Error("CST should contain source_file")
	}
	if !strings.Contains(cst, "function_declaration") {
		t.Error("CST should contain function_declaration")
	}
	if !strings.Contains(cst, "├──") || !strings.Contains(cst, "└──") {
		t.Error("CST should use tree characters")
	}
}

func TestRenderCST_DepthLimit(t *testing.T) {
	source := "package main\n\nfunc main() {\n\tx := 1\n}\n"
	tree := parseSource(t, source, "go")

	full := RenderCST(tree, 0)
	limited := RenderCST(tree, 2)

	if len(limited) >= len(full) {
		t.Error("depth-limited CST should be shorter than full CST")
	}
}

// --- Markdown writer tests ---

func TestSanitizePath(t *testing.T) {
	cases := []struct {
		input    string
		expected string
	}{
		{"main.go", "main.go"},
		{"internal/handler/user.go", "internal_handler_user.go"},
		{"./src/index.ts", "src_index.ts"},
	}
	for _, tc := range cases {
		got := SanitizePath(tc.input)
		if got != tc.expected {
			t.Errorf("SanitizePath(%q) = %q, want %q", tc.input, got, tc.expected)
		}
	}
}

func TestWriteFileMD(t *testing.T) {
	source := "package main\n\nfunc main() {}\n"
	tree := parseSource(t, source, "go")
	outDir := t.TempDir()

	err := WriteFileMD(tree, "main.go", outDir, ModeSummary, 0)
	if err != nil {
		t.Fatalf("WriteFileMD: %v", err)
	}

	content, err := readFile(outDir + "/files/main.go.md")
	if err != nil {
		t.Fatalf("reading output: %v", err)
	}

	if !strings.HasPrefix(content, "---\n") {
		t.Error("output should start with frontmatter")
	}
	if !strings.Contains(content, "language: go") {
		t.Error("output should contain language field")
	}
}

// --- Index tests ---

func TestWriteIndexMD(t *testing.T) {
	files := []*FileInfo{
		{File: "main.go", Language: "go", FunctionCount: 2, TypeCount: 0, Lines: 30},
		{File: "utils.go", Language: "go", FunctionCount: 5, TypeCount: 1, Lines: 80},
	}
	outDir := t.TempDir()

	err := WriteIndexMD(files, "/project", outDir)
	if err != nil {
		t.Fatalf("WriteIndexMD: %v", err)
	}

	content, err := readFile(outDir + "/index.md")
	if err != nil {
		t.Fatalf("reading index: %v", err)
	}

	if !strings.HasPrefix(content, "---\n") {
		t.Error("index should start with frontmatter")
	}
	if !strings.Contains(content, "total_files: 2") {
		t.Error("index should contain total_files")
	}
	if !strings.Contains(content, "main.go") {
		t.Error("index should list main.go")
	}
	if !strings.Contains(content, "utils.go") {
		t.Error("index should list utils.go")
	}
}

func readFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	return string(b), err
}
