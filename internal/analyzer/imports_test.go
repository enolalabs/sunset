package analyzer

import (
	"testing"

	"github.com/enolalabs/sunset/internal/output"
)

func TestExtractAndResolve_GoInternal(t *testing.T) {
	info := &output.FileInfo{
		File:     "cmd/main.go",
		Language: "go",
		Imports: []output.ImportInfo{
			{Path: "fmt", Line: 3},
			{Path: "net/http", Line: 4},
		},
	}
	projectFiles := []string{"cmd/main.go", "internal/handler/user.go"}

	result := ExtractAndResolve(info, projectFiles, "/tmp/test")
	if len(result) != 2 {
		t.Fatalf("expected 2 imports, got %d", len(result))
	}

	// fmt should be external (stdlib)
	if result[0].Status != StatusExternal {
		t.Errorf("expected fmt to be external, got %s", result[0].Status)
	}
	// net/http should be external (stdlib)
	if result[1].Status != StatusExternal {
		t.Errorf("expected net/http to be external, got %s", result[1].Status)
	}
}

func TestExtractAndResolve_JSRelative(t *testing.T) {
	info := &output.FileInfo{
		File:     "src/index.ts",
		Language: "typescript",
		Imports: []output.ImportInfo{
			{Path: "./utils/helper", Line: 1},
			{Path: "react", Line: 2},
		},
	}
	projectFiles := []string{"src/index.ts", "src/utils/helper.ts"}

	result := ExtractAndResolve(info, projectFiles, "/tmp/test")
	if len(result) != 2 {
		t.Fatalf("expected 2 imports, got %d", len(result))
	}

	// Relative import should be resolved
	if result[0].Status != StatusResolved {
		t.Errorf("expected ./utils/helper to be resolved, got %s", result[0].Status)
	}
	if result[0].Resolved != "src/utils/helper.ts" {
		t.Errorf("expected resolved path 'src/utils/helper.ts', got %q", result[0].Resolved)
	}

	// react should be external
	if result[1].Status != StatusExternal {
		t.Errorf("expected react to be external, got %s", result[1].Status)
	}
}

func TestExtractAndResolve_PythonRelative(t *testing.T) {
	info := &output.FileInfo{
		File:     "app/main.py",
		Language: "python",
		Imports: []output.ImportInfo{
			{Path: "models.user", Line: 1},
		},
	}
	projectFiles := []string{"app/main.py", "models/user.py"}

	result := ExtractAndResolve(info, projectFiles, "/tmp/test")
	if len(result) != 1 {
		t.Fatalf("expected 1 import, got %d", len(result))
	}

	if result[0].Status != StatusResolved {
		t.Errorf("expected models.user to be resolved, got %s", result[0].Status)
	}
}

func TestExtractAndResolve_Unresolved(t *testing.T) {
	info := &output.FileInfo{
		File:     "main.py",
		Language: "python",
		Imports: []output.ImportInfo{
			{Path: "nonexistent.module", Line: 1},
		},
	}
	result := ExtractAndResolve(info, []string{"main.py"}, "/tmp/test")

	if result[0].Status != StatusUnresolved {
		t.Errorf("expected unresolved, got %s", result[0].Status)
	}
}
