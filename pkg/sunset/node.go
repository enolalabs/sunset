package sunset

import (
	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// Node wraps a tree-sitter node with convenience methods.
type Node struct {
	raw    *tree_sitter.Node
	source []byte
}

// newNode creates a Node wrapper.
func newNode(raw *tree_sitter.Node, source []byte) *Node {
	if raw == nil {
		return nil
	}
	return &Node{raw: raw, source: source}
}

// Raw returns the underlying tree-sitter Node for advanced usage.
func (n *Node) Raw() *tree_sitter.Node {
	return n.raw
}

// Type returns the grammar type of this node (e.g., "function_declaration").
func (n *Node) Type() string {
	return n.raw.Kind()
}

// Text returns the source text covered by this node.
func (n *Node) Text() string {
	return n.raw.Utf8Text(n.source)
}

// Position returns the start position of this node.
func (n *Node) Position() Position {
	p := n.raw.StartPosition()
	return Position{
		Row:    int(p.Row),
		Column: int(p.Column),
	}
}

// EndPosition returns the end position of this node.
func (n *Node) EndPosition() Position {
	p := n.raw.EndPosition()
	return Position{
		Row:    int(p.Row),
		Column: int(p.Column),
	}
}

// Position represents a line/column position in source code.
type Position struct {
	Row    int
	Column int
}

// Children returns all child nodes.
func (n *Node) Children() []*Node {
	count := int(n.raw.ChildCount())
	children := make([]*Node, 0, count)
	for i := 0; i < count; i++ {
		child := n.raw.Child(uint(i))
		if child != nil {
			children = append(children, newNode(child, n.source))
		}
	}
	return children
}

// NamedChildren returns only named child nodes (excludes punctuation, keywords).
func (n *Node) NamedChildren() []*Node {
	count := int(n.raw.NamedChildCount())
	children := make([]*Node, 0, count)
	for i := 0; i < count; i++ {
		child := n.raw.NamedChild(uint(i))
		if child != nil {
			children = append(children, newNode(child, n.source))
		}
	}
	return children
}

// ChildByFieldName returns a child node by its field name in the grammar.
func (n *Node) ChildByFieldName(name string) *Node {
	child := n.raw.ChildByFieldName(name)
	return newNode(child, n.source)
}

// Parent returns the parent node, or nil for the root.
func (n *Node) Parent() *Node {
	parent := n.raw.Parent()
	return newNode(parent, n.source)
}

// IsNamed returns true if this is a named node in the grammar.
func (n *Node) IsNamed() bool {
	return n.raw.IsNamed()
}

// IsError returns true if this node represents a syntax error.
func (n *Node) IsError() bool {
	return n.raw.IsError()
}

// IsMissing returns true if this node was inserted by error recovery.
func (n *Node) IsMissing() bool {
	return n.raw.IsMissing()
}

// ChildCount returns the number of children.
func (n *Node) ChildCount() int {
	return int(n.raw.ChildCount())
}

// TreeWrapper wraps a parsed tree with high-level traversal methods.
type TreeWrapper struct {
	tree   *parser.Tree
	source []byte
}

// newTreeWrapper creates a TreeWrapper.
func newTreeWrapper(tree *parser.Tree) *TreeWrapper {
	return &TreeWrapper{
		tree:   tree,
		source: tree.Source(),
	}
}

// RootNode returns the root node of the syntax tree.
func (tw *TreeWrapper) RootNode() *Node {
	return newNode(tw.tree.RootNode(), tw.source)
}

// Walk performs a depth-first traversal of the entire tree.
// The callback receives each node and its depth.
// Return true to continue into children, false to skip.
func (tw *TreeWrapper) Walk(fn func(node *Node, depth int) bool) {
	parser.Walk(tw.tree.RootNode(), func(raw *tree_sitter.Node, depth int) bool {
		return fn(newNode(raw, tw.source), depth)
	})
}

// Filter returns all nodes in the tree matching the given type.
func (tw *TreeWrapper) Filter(nodeType string) []*Node {
	rawNodes := parser.Filter(tw.tree.RootNode(), nodeType)
	nodes := make([]*Node, len(rawNodes))
	for i, raw := range rawNodes {
		nodes[i] = newNode(raw, tw.source)
	}
	return nodes
}
