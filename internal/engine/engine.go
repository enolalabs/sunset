// Package engine orchestrates scanning, parsing, caching, and output generation.
package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"

	"github.com/enolalabs/sunset/internal/cache"
	"github.com/enolalabs/sunset/internal/language"
	"github.com/enolalabs/sunset/internal/output"
	"github.com/enolalabs/sunset/internal/parser"
	"github.com/enolalabs/sunset/internal/scanner"
)

// Config holds engine configuration.
type Config struct {
	RootDir     string
	OutputDir   string
	Mode        output.Mode
	MaxDepth    int
	Exclude     []string
	Concurrency int
	NoCache     bool
}

// Result holds the outcome of a run.
type Result struct {
	TotalFiles   int
	ParsedFiles  int
	SkippedFiles int
	RemovedFiles int
	Duration     time.Duration
	Errors       []FileError
}

// FileError records a per-file error.
type FileError struct {
	File  string
	Error error
}

// Run performs a full or incremental parse of the project.
func Run(cfg *Config) (*Result, error) {
	start := time.Now()

	if cfg.Concurrency <= 0 {
		cfg.Concurrency = runtime.NumCPU()
	}
	if cfg.OutputDir == "" {
		cfg.OutputDir = filepath.Join(cfg.RootDir, ".sunset", "output")
	}

	// 1. Scan files
	scanResult, err := scanner.Scan(cfg.RootDir, &scanner.Options{
		ExcludePatterns: cfg.Exclude,
	})
	if err != nil {
		return nil, fmt.Errorf("scanning: %w", err)
	}

	result := &Result{TotalFiles: len(scanResult.Files)}

	// 2. Load cache
	var c *cache.Cache
	if !cfg.NoCache {
		c, err = cache.Load(cfg.RootDir)
		if err != nil {
			return nil, fmt.Errorf("loading cache: %w", err)
		}
		// Prune deleted files
		removed := c.Prune(scanResult.Files)
		result.RemovedFiles = len(removed)
	}

	// 3. Determine which files to parse
	type parseJob struct {
		relPath string
		content []byte
		hash    string
	}

	var jobs []parseJob
	for _, relPath := range scanResult.Files {
		absPath := filepath.Join(cfg.RootDir, relPath)
		content, err := os.ReadFile(absPath)
		if err != nil {
			result.Errors = append(result.Errors, FileError{File: relPath, Error: err})
			continue
		}

		hash := cache.HashContent(content)
		if c != nil && !c.IsChangedByHash(relPath, hash) {
			result.SkippedFiles++
			continue
		}

		jobs = append(jobs, parseJob{relPath: relPath, content: content, hash: hash})
	}

	// 4. Parse files (parallel)
	type parseResult struct {
		relPath string
		info    *output.FileInfo
		tree    *parser.Tree
		err     error
	}

	results := make([]parseResult, len(jobs))
	var wg sync.WaitGroup
	sem := make(chan struct{}, cfg.Concurrency)

	for i, job := range jobs {
		wg.Add(1)
		go func(idx int, j parseJob) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			defer func() {
				if r := recover(); r != nil {
					results[idx] = parseResult{relPath: j.relPath, err: fmt.Errorf("panic: %v", r)}
				}
			}()

			pr := parseResult{relPath: j.relPath}

			lang, langErr := language.Detect(filepath.Base(j.relPath))
			if langErr != nil {
				pr.err = langErr
				results[idx] = pr
				return
			}

			p := parser.NewParser()
			defer p.Close()

			if setErr := p.SetLanguage(lang.Grammar); setErr != nil {
				pr.err = setErr
				results[idx] = pr
				return
			}

			tree, parseErr := p.Parse(j.content, lang.ID)
			if parseErr != nil {
				pr.err = parseErr
				results[idx] = pr
				return
			}

			pr.info = output.ExtractFileInfo(tree, j.relPath)
			pr.tree = tree
			results[idx] = pr
		}(i, job)
	}
	wg.Wait()

	// 5. Write output + update cache
	var allInfos []*output.FileInfo
	for i, pr := range results {
		if pr.err != nil {
			result.Errors = append(result.Errors, FileError{File: pr.relPath, Error: pr.err})
			continue
		}
		if pr.tree == nil {
			continue
		}

		// Write markdown file
		if writeErr := output.WriteFileMD(pr.tree, pr.relPath, cfg.OutputDir, cfg.Mode, cfg.MaxDepth); writeErr != nil {
			result.Errors = append(result.Errors, FileError{File: pr.relPath, Error: writeErr})
		}

		// Update cache
		if c != nil {
			c.UpdateWithHash(pr.relPath, jobs[i].hash, pr.info.Language)
		}

		allInfos = append(allInfos, pr.info)
		pr.tree.Close()
		result.ParsedFiles++
	}

	// 6. Write index.md
	if len(allInfos) > 0 || result.RemovedFiles > 0 {
		if writeErr := output.WriteIndexMD(allInfos, cfg.RootDir, cfg.OutputDir); writeErr != nil {
			return nil, fmt.Errorf("writing index: %w", writeErr)
		}
	}

	// 7. Save cache
	if c != nil {
		if saveErr := c.Save(); saveErr != nil {
			return nil, fmt.Errorf("saving cache: %w", saveErr)
		}
	}

	result.Duration = time.Since(start)
	return result, nil
}
