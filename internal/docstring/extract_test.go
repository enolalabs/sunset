package docstring

import (
	"testing"

	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_go "github.com/tree-sitter/tree-sitter-go/bindings/go"
	tree_sitter_python "github.com/tree-sitter/tree-sitter-python/bindings/go"
	tree_sitter_typescript "github.com/tree-sitter/tree-sitter-typescript/bindings/go"
)

func parseAndGetFuncs(t *testing.T, source string, langID string, nodeType string) ([]*tree_sitter.Node, []byte) {
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

	src := []byte(source)
	tree, err := p.Parse(src, langID)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	t.Cleanup(tree.Close)

	funcs := parser.Filter(tree.RootNode(), nodeType)
	return funcs, src
}

func TestExtract_GoDocstring(t *testing.T) {
	source := `package main

// Hello greets the user.
func Hello() {}

func NoDoc() {}
`
	funcs, src := parseAndGetFuncs(t, source, "go", "function_declaration")

	if len(funcs) < 2 {
		t.Fatalf("expected 2 functions, got %d", len(funcs))
	}

	doc := Extract(funcs[0], src, "go")
	if doc == "" {
		t.Error("expected docstring for Hello")
	}
	if doc != "Hello greets the user." {
		t.Errorf("unexpected doc: %q", doc)
	}

	doc2 := Extract(funcs[1], src, "go")
	if doc2 != "" {
		t.Errorf("expected empty docstring for NoDoc, got %q", doc2)
	}
}

func TestExtract_PythonDocstring(t *testing.T) {
	source := `def create_user(name):
    """Create a new user with the given name."""
    pass

def no_doc():
    pass
`
	funcs, src := parseAndGetFuncs(t, source, "python", "function_definition")

	if len(funcs) < 2 {
		t.Fatalf("expected 2 functions, got %d", len(funcs))
	}

	doc := Extract(funcs[0], src, "python")
	if doc == "" {
		t.Error("expected docstring for create_user")
	}
	if doc != "Create a new user with the given name." {
		t.Errorf("unexpected doc: %q", doc)
	}

	doc2 := Extract(funcs[1], src, "python")
	if doc2 != "" {
		t.Errorf("expected empty doc for no_doc, got %q", doc2)
	}
}

func TestExtract_JSDocComment(t *testing.T) {
	source := `/**
 * Fetches a user by ID.
 * @param id - User ID
 */
function getUser(id: string) {
  return id;
}

function noDoc() {}
`
	funcs, src := parseAndGetFuncs(t, source, "typescript", "function_declaration")

	if len(funcs) < 1 {
		t.Fatalf("expected at least 1 function, got %d", len(funcs))
	}

	doc := Extract(funcs[0], src, "typescript")
	if doc == "" {
		t.Error("expected JSDoc for getUser")
	}
}
