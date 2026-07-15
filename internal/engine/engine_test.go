package engine

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/enolalabs/sunset/internal/cache"
	"github.com/enolalabs/sunset/internal/output"
)

func setupTestProject(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()

	// Create a Go file
	if err := os.WriteFile(filepath.Join(tmp, "main.go"), []byte(`package main

import "fmt"

func main() {
	fmt.Println("hello")
}
`), 0644); err != nil {
		t.Fatal(err)
	}

	// Create a Python file
	if err := os.WriteFile(filepath.Join(tmp, "app.py"), []byte(`def hello():
    """Say hello."""
    print("hello")
`), 0644); err != nil {
		t.Fatal(err)
	}

	return tmp
}

func TestRun_FullParse(t *testing.T) {
	tmp := setupTestProject(t)
	outDir := filepath.Join(tmp, ".sunset", "output")

	result, err := Run(&Config{
		RootDir:   tmp,
		OutputDir: outDir,
		Mode:      output.ModeSummary,
		NoCache:   true,
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}

	if result.TotalFiles != 2 {
		t.Errorf("expected 2 total files, got %d", result.TotalFiles)
	}
	if result.ParsedFiles != 2 {
		t.Errorf("expected 2 parsed files, got %d", result.ParsedFiles)
	}

	// Check index.md exists
	indexPath := filepath.Join(outDir, "index.md")
	if _, err := os.Stat(indexPath); err != nil {
		t.Errorf("index.md not created: %v", err)
	}

	// Check file outputs exist
	filesDir := filepath.Join(outDir, "files")
	entries, err := os.ReadDir(filesDir)
	if err != nil {
		t.Fatalf("reading files dir: %v", err)
	}
	if len(entries) != 2 {
		t.Errorf("expected 2 output files, got %d", len(entries))
	}
}

func TestRun_IncrementalSkipsUnchanged(t *testing.T) {
	tmp := setupTestProject(t)
	outDir := filepath.Join(tmp, ".sunset", "output")

	cfg := &Config{
		RootDir:   tmp,
		OutputDir: outDir,
		Mode:      output.ModeSummary,
	}

	// First run — parses all
	r1, err := Run(cfg)
	if err != nil {
		t.Fatalf("Run 1: %v", err)
	}
	if r1.ParsedFiles != 2 {
		t.Errorf("first run: expected 2 parsed, got %d", r1.ParsedFiles)
	}

	// Second run — should skip everything
	r2, err := Run(cfg)
	if err != nil {
		t.Fatalf("Run 2: %v", err)
	}
	if r2.SkippedFiles != 2 {
		t.Errorf("second run: expected 2 skipped, got %d (parsed=%d)", r2.SkippedFiles, r2.ParsedFiles)
	}
	if r2.ParsedFiles != 0 {
		t.Errorf("second run: expected 0 parsed, got %d", r2.ParsedFiles)
	}
}

func TestRun_IncrementalDetectsChanges(t *testing.T) {
	tmp := setupTestProject(t)
	outDir := filepath.Join(tmp, ".sunset", "output")

	cfg := &Config{
		RootDir:   tmp,
		OutputDir: outDir,
		Mode:      output.ModeSummary,
	}

	// First run
	if _, err := Run(cfg); err != nil {
		t.Fatalf("Run 1: %v", err)
	}

	// Modify a file
	if err := os.WriteFile(filepath.Join(tmp, "main.go"), []byte(`package main

import "fmt"

func main() {
	fmt.Println("modified")
}

func newFunc() {}
`), 0644); err != nil {
		t.Fatal(err)
	}

	// Second run — should parse the modified file
	r2, err := Run(cfg)
	if err != nil {
		t.Fatalf("Run 2: %v", err)
	}
	if r2.ParsedFiles != 1 {
		t.Errorf("expected 1 re-parsed file, got %d", r2.ParsedFiles)
	}
	if r2.SkippedFiles != 1 {
		t.Errorf("expected 1 skipped file, got %d", r2.SkippedFiles)
	}
}

func TestRun_DetectsDeletedFiles(t *testing.T) {
	tmp := setupTestProject(t)

	cfg := &Config{
		RootDir:   tmp,
		OutputDir: filepath.Join(tmp, ".sunset", "output"),
		Mode:      output.ModeSummary,
	}

	// First run
	if _, err := Run(cfg); err != nil {
		t.Fatal(err)
	}

	// Delete a file
	os.Remove(filepath.Join(tmp, "app.py"))

	// Second run
	r2, err := Run(cfg)
	if err != nil {
		t.Fatalf("Run 2: %v", err)
	}
	if r2.RemovedFiles != 1 {
		t.Errorf("expected 1 removed file, got %d", r2.RemovedFiles)
	}
}

func TestRun_DetectsNewFiles(t *testing.T) {
	tmp := setupTestProject(t)

	cfg := &Config{
		RootDir:   tmp,
		OutputDir: filepath.Join(tmp, ".sunset", "output"),
		Mode:      output.ModeSummary,
	}

	// First run
	if _, err := Run(cfg); err != nil {
		t.Fatal(err)
	}

	// Add new file
	if err := os.WriteFile(filepath.Join(tmp, "new.go"), []byte("package main\nfunc New() {}\n"), 0644); err != nil {
		t.Fatal(err)
	}

	r2, err := Run(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if r2.ParsedFiles != 1 {
		t.Errorf("expected 1 new parsed file, got %d", r2.ParsedFiles)
	}
}

func TestRun_ParallelSameAsSequential(t *testing.T) {
	tmp := setupTestProject(t)

	// Sequential
	r1, err := Run(&Config{
		RootDir:     tmp,
		OutputDir:   filepath.Join(tmp, "out1"),
		Mode:        output.ModeSummary,
		Concurrency: 1,
		NoCache:     true,
	})
	if err != nil {
		t.Fatal(err)
	}

	// Parallel
	r2, err := Run(&Config{
		RootDir:     tmp,
		OutputDir:   filepath.Join(tmp, "out2"),
		Mode:        output.ModeSummary,
		Concurrency: 4,
		NoCache:     true,
	})
	if err != nil {
		t.Fatal(err)
	}

	if r1.ParsedFiles != r2.ParsedFiles {
		t.Errorf("sequential parsed %d, parallel parsed %d", r1.ParsedFiles, r2.ParsedFiles)
	}
	if r1.TotalFiles != r2.TotalFiles {
		t.Errorf("sequential total %d, parallel total %d", r1.TotalFiles, r2.TotalFiles)
	}
}

func TestRun_CleanCache(t *testing.T) {
	tmp := setupTestProject(t)

	// Run to create cache
	if _, err := Run(&Config{
		RootDir: tmp,
		Mode:    output.ModeSummary,
	}); err != nil {
		t.Fatal(err)
	}

	// Verify cache exists
	if _, err := os.Stat(filepath.Join(tmp, cache.CacheDir)); err != nil {
		t.Fatal("cache should exist after run")
	}

	// Clean
	if err := cache.Clean(tmp); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(tmp, cache.CacheDir)); !os.IsNotExist(err) {
		t.Error("cache should be cleaned")
	}
}
