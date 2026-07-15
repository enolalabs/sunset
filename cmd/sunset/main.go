package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/enolalabs/sunset/internal/engine"
	"github.com/enolalabs/sunset/internal/language"
	"github.com/enolalabs/sunset/internal/output"
	"github.com/enolalabs/sunset/internal/version"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(0)
	}

	cmd := os.Args[1]

	// Handle --help and --version at root level
	if cmd == "--help" || cmd == "-h" {
		printUsage()
		os.Exit(0)
	}
	if cmd == "--version" || cmd == "-v" {
		fmt.Printf("sunset %s\n", version.Current())
		os.Exit(0)
	}

	switch cmd {
	case "parse":
		cmdParse(os.Args[2:])
	case "update":
		cmdUpdate(os.Args[2:])
	case "languages":
		cmdLanguages()
	case "version":
		fmt.Printf("sunset %s\n", version.Current())
	case "clean":
		cmdClean(os.Args[2:])
	case "help":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown command %q\n\n", cmd)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("🌅 Sunset — Codebase Indexer")
	fmt.Printf("Version: %s\n\n", version.Current())
	fmt.Println("Usage: sunset <command> [flags]")
	fmt.Println()
	fmt.Println("Commands:")
	fmt.Println("  parse      Parse a file or directory into Markdown")
	fmt.Println("  update     Incremental update (re-parse changed files only)")
	fmt.Println("  languages  List supported languages and extensions")
	fmt.Println("  version    Show version info")
	fmt.Println("  clean      Remove cache and output directories")
	fmt.Println("  help       Show this help message")
	fmt.Println()
	fmt.Println("Run 'sunset <command> --help' for details on each command.")
}

// --- parse command ---

func cmdParse(args []string) {
	fs := flag.NewFlagSet("parse", flag.ExitOnError)
	outputDir := fs.String("output", "", "Output directory (default: <path>/.sunset/output)")
	detail := fs.String("detail", "summary", "Detail level: summary or full")
	exclude := fs.String("exclude", "", "Comma-separated glob patterns to exclude")
	concurrency := fs.Int("concurrency", 0, "Max parallel parsers (default: NumCPU)")
	noCache := fs.Bool("no-cache", false, "Disable caching, force full re-parse")
	maxDepth := fs.Int("max-depth", 0, "Max tree depth for full CST mode (0=unlimited)")
	quiet := fs.Bool("quiet", false, "Suppress output except errors")

	fs.Usage = func() {
		fmt.Println("Usage: sunset parse <path> [flags]")
		fmt.Println()
		fmt.Println("Parse a file or directory and generate Markdown documentation.")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	mode := output.ModeSummary
	if *detail == "full" {
		mode = output.ModeFullCST
	}

	runEngine(fs.Arg(0), *outputDir, *exclude, *concurrency, *noCache, *quiet, mode, *maxDepth)
}

// --- update command ---

func cmdUpdate(args []string) {
	fs := flag.NewFlagSet("update", flag.ExitOnError)
	outputDir := fs.String("output", "", "Output directory")
	exclude := fs.String("exclude", "", "Comma-separated glob patterns to exclude")
	concurrency := fs.Int("concurrency", 0, "Max parallel parsers")
	quiet := fs.Bool("quiet", false, "Suppress output except errors")

	fs.Usage = func() {
		fmt.Println("Usage: sunset update [path] [flags]")
		fmt.Println()
		fmt.Println("Incrementally update: only re-parse changed files.")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	runEngine(fs.Arg(0), *outputDir, *exclude, *concurrency, false, *quiet, output.ModeSummary, 0)
}

// runEngine is the shared logic for parse and update commands.
func runEngine(pathArg, outputDir, exclude string, concurrency int, noCache, quiet bool, mode output.Mode, maxDepth int) {
	path := pathArg
	if path == "" {
		path = "."
	}

	// Validate path
	if _, err := os.Stat(path); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	var excludePatterns []string
	if exclude != "" {
		for _, p := range strings.Split(exclude, ",") {
			excludePatterns = append(excludePatterns, strings.TrimSpace(p))
		}
	}

	cfg := &engine.Config{
		RootDir:     path,
		OutputDir:   outputDir,
		Mode:        mode,
		MaxDepth:    maxDepth,
		Exclude:     excludePatterns,
		Concurrency: concurrency,
		NoCache:     noCache,
	}

	if !quiet {
		fmt.Printf("🌅 Parsing %s ...\n", path)
	}

	result, err := engine.Run(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if !quiet {
		printResult(result)
	}

	if len(result.Errors) > 0 {
		os.Exit(1)
	}
}

// --- languages command ---

func cmdLanguages() {
	langs := language.Supported()
	fmt.Println("Supported languages:")
	fmt.Println()
	fmt.Printf("  %-15s %s\n", "Language", "Extensions")
	fmt.Printf("  %-15s %s\n", "--------", "----------")
	for _, l := range langs {
		fmt.Printf("  %-15s %s\n", l.ID, strings.Join(l.Extensions, ", "))
	}
}

// --- clean command ---

func cmdClean(args []string) {
	fs := flag.NewFlagSet("clean", flag.ExitOnError)
	quiet := fs.Bool("quiet", false, "Suppress output")

	fs.Usage = func() {
		fmt.Println("Usage: sunset clean [path]")
		fmt.Println()
		fmt.Println("Remove .sunset/ directory (cache + output).")
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	path := fs.Arg(0)
	if path == "" {
		path = "."
	}

	// Remove .sunset directory (contains both cache and output)
	if err := os.RemoveAll(filepath.Join(path, ".sunset")); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not clean .sunset: %v\n", err)
	}

	if !*quiet {
		fmt.Println("✨ Cleaned cache and output directories.")
	}
}

// --- helpers ---

func printResult(r *engine.Result) {
	fmt.Println()
	fmt.Printf("  📁 Total files:   %d\n", r.TotalFiles)
	fmt.Printf("  ✅ Parsed:        %d\n", r.ParsedFiles)
	fmt.Printf("  ⏭️  Skipped:       %d\n", r.SkippedFiles)
	if r.RemovedFiles > 0 {
		fmt.Printf("  🗑️  Removed:       %d\n", r.RemovedFiles)
	}
	fmt.Printf("  ⏱️  Duration:      %s\n", formatDuration(r.Duration))

	if len(r.Errors) > 0 {
		fmt.Printf("\n  ⚠️  Errors: %d\n", len(r.Errors))
		for _, e := range r.Errors {
			fmt.Printf("    • %s: %v\n", e.File, e.Error)
		}
	}

	fmt.Println()
}

func formatDuration(d time.Duration) string {
	if d < time.Millisecond {
		return fmt.Sprintf("%dµs", d.Microseconds())
	}
	if d < time.Second {
		return fmt.Sprintf("%dms", d.Milliseconds())
	}
	return fmt.Sprintf("%.2fs", d.Seconds())
}
