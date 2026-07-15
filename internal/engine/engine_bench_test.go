package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/enolalabs/sunset/internal/output"
)

func setupBenchProject(b *testing.B, numFiles int) string {
	b.Helper()
	tmp := b.TempDir()

	for i := 0; i < numFiles; i++ {
		content := fmt.Sprintf(`package main

import "fmt"

// Handler%d handles request %d.
func Handler%d() {
	fmt.Println("handler %d")
}

func helper%d() string {
	return "helper"
}
`, i, i, i, i, i)
		filename := fmt.Sprintf("handler_%d.go", i)
		if err := os.WriteFile(filepath.Join(tmp, filename), []byte(content), 0644); err != nil {
			b.Fatal(err)
		}
	}
	return tmp
}

func BenchmarkRun_FullParse_50Files(b *testing.B) {
	tmp := setupBenchProject(b, 50)
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		outDir := filepath.Join(tmp, fmt.Sprintf("out-%d", i))
		_, err := Run(&Config{
			RootDir:   tmp,
			OutputDir: outDir,
			Mode:      output.ModeSummary,
			NoCache:   true,
		})
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkRun_Incremental_50Files_1Changed(b *testing.B) {
	tmp := setupBenchProject(b, 50)
	outDir := filepath.Join(tmp, "out")

	// First run to populate cache
	_, err := Run(&Config{
		RootDir:   tmp,
		OutputDir: outDir,
		Mode:      output.ModeSummary,
	})
	if err != nil {
		b.Fatal(err)
	}

	// Modify one file
	if err := os.WriteFile(filepath.Join(tmp, "handler_0.go"), []byte(`package main

import "fmt"

func Handler0Modified() {
	fmt.Println("modified")
}
`), 0644); err != nil {
		b.Fatal(err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := Run(&Config{
			RootDir:   tmp,
			OutputDir: outDir,
			Mode:      output.ModeSummary,
		})
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkRun_Parallel_vs_Sequential(b *testing.B) {
	tmp := setupBenchProject(b, 50)

	b.Run("sequential", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			outDir := filepath.Join(tmp, fmt.Sprintf("seq-%d", i))
			_, err := Run(&Config{
				RootDir:     tmp,
				OutputDir:   outDir,
				Mode:        output.ModeSummary,
				Concurrency: 1,
				NoCache:     true,
			})
			if err != nil {
				b.Fatal(err)
			}
		}
	})

	b.Run("parallel", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			outDir := filepath.Join(tmp, fmt.Sprintf("par-%d", i))
			_, err := Run(&Config{
				RootDir:     tmp,
				OutputDir:   outDir,
				Mode:        output.ModeSummary,
				Concurrency: 4,
				NoCache:     true,
			})
			if err != nil {
				b.Fatal(err)
			}
		}
	})
}
