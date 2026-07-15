package output

import (
	"fmt"
	"strings"

	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// RenderCST generates the full concrete syntax tree as formatted text.
func RenderCST(tree *parser.Tree, maxDepth int) string {
	var b strings.Builder
	b.WriteString("\n## Concrete Syntax Tree\n\n")
	b.WriteString("```\n")
	renderCSTNode(&b, tree.RootNode(), tree.Source(), 0, maxDepth, true)
	b.WriteString("```\n")
	return b.String()
}

func renderCSTNode(b *strings.Builder, node *tree_sitter.Node, source []byte, depth int, maxDepth int, isLast bool) {
	if node == nil {
		return
	}

	// Respect depth limit (0 = unlimited)
	if maxDepth > 0 && depth > maxDepth {
		return
	}

	// Indent with tree characters
	if depth > 0 {
		for i := 0; i < depth-1; i++ {
			b.WriteString("│   ")
		}
		if isLast {
			b.WriteString("└── ")
		} else {
			b.WriteString("├── ")
		}
	}

	// Node info
	startPos := node.StartPosition()
	endPos := node.EndPosition()
	b.WriteString(fmt.Sprintf("%s [%d:%d-%d:%d]",
		node.Kind(),
		startPos.Row, startPos.Column,
		endPos.Row, endPos.Column,
	))

	// Show text for leaf nodes
	if node.ChildCount() == 0 {
		text := node.Utf8Text(source)
		if len(text) > 40 {
			text = text[:40] + "..."
		}
		// Escape newlines for display
		text = strings.ReplaceAll(text, "\n", "\\n")
		b.WriteString(fmt.Sprintf(" %q", text))
	}

	b.WriteString("\n")

	// Render children
	childCount := int(node.ChildCount())
	for i := 0; i < childCount; i++ {
		child := node.Child(uint(i))
		if child != nil {
			renderCSTNode(b, child, source, depth+1, maxDepth, i == childCount-1)
		}
	}
}
