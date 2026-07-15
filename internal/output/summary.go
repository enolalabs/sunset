package output

import (
	"bytes"
	"fmt"
	"strings"

	"github.com/enolalabs/sunset/internal/docstring"
	"github.com/enolalabs/sunset/internal/parser"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
)

// ExtractFileInfo analyzes a parsed tree and extracts structured information.
func ExtractFileInfo(tree *parser.Tree, filePath string) *FileInfo {
	root := tree.RootNode()
	source := tree.Source()
	langID := tree.Language

	info := &FileInfo{
		File:     filePath,
		Language: langID,
		Lines:    countLines(source),
	}

	// Extract package name (Go)
	info.Package = extractPackage(root, source, langID)

	// Extract functions
	info.Functions = extractFunctions(root, source, langID)
	info.FunctionCount = len(info.Functions)

	// Extract types
	info.Types = extractTypes(root, source, langID)
	info.TypeCount = len(info.Types)

	// Extract imports
	info.Imports = extractImports(root, source, langID)
	info.ImportCount = len(info.Imports)

	// Extract constants
	info.Constants = extractConstants(root, source, langID)

	// Generate tags
	info.Tags = generateTags(info, langID)

	return info
}

// RenderSummary generates the Markdown body for summary mode.
func RenderSummary(info *FileInfo) string {
	var b strings.Builder

	// Functions section
	if len(info.Functions) > 0 {
		b.WriteString("\n## Functions\n")
		for _, f := range info.Functions {
			b.WriteString(fmt.Sprintf("\n### %s\n", f.Name))
			b.WriteString(fmt.Sprintf("- **Signature**: `%s`\n", f.Signature))
			b.WriteString(fmt.Sprintf("- **Line**: %d-%d\n", f.StartLine, f.EndLine))
			if f.Receiver != "" {
				b.WriteString(fmt.Sprintf("- **Receiver**: %s\n", f.Receiver))
			}
			if f.Doc != "" {
				b.WriteString(fmt.Sprintf("- **Doc**: %s\n", f.Doc))
			}
		}
	}

	// Types section
	if len(info.Types) > 0 {
		b.WriteString("\n## Types\n")
		for _, t := range info.Types {
			b.WriteString(fmt.Sprintf("\n### %s\n", t.Name))
			b.WriteString(fmt.Sprintf("- **Kind**: %s\n", t.Kind))
			b.WriteString(fmt.Sprintf("- **Line**: %d-%d\n", t.StartLine, t.EndLine))
			if t.Doc != "" {
				b.WriteString(fmt.Sprintf("- **Doc**: %s\n", t.Doc))
			}
			if len(t.Fields) > 0 {
				fields := make([]string, len(t.Fields))
				for i, f := range t.Fields {
					fields[i] = fmt.Sprintf("%s (%s)", f.Name, f.Type)
				}
				b.WriteString(fmt.Sprintf("- **Fields**: %s\n", strings.Join(fields, ", ")))
			}
		}
	}

	// Imports section
	if len(info.Imports) > 0 {
		b.WriteString("\n## Imports\n\n")
		b.WriteString("| Import | Line |\n")
		b.WriteString("|---|---|\n")
		for _, imp := range info.Imports {
			display := imp.Path
			if imp.Alias != "" {
				display = fmt.Sprintf("%s (as %s)", imp.Path, imp.Alias)
			}
			b.WriteString(fmt.Sprintf("| %s | %d |\n", display, imp.Line))
		}
	}

	// Constants section
	if len(info.Constants) > 0 {
		b.WriteString("\n## Constants\n\n")
		for _, c := range info.Constants {
			val := c.Value
			if len(val) > 50 {
				val = val[:50] + "..."
			}
			b.WriteString(fmt.Sprintf("- **%s** = `%s` [line %d]\n", c.Name, val, c.StartLine))
		}
	}

	return b.String()
}

// --- Extractors ---

func extractPackage(root *tree_sitter.Node, source []byte, langID string) string {
	switch langID {
	case "go":
		pkgs := parser.Filter(root, "package_clause")
		if len(pkgs) > 0 {
			nameNode := pkgs[0].ChildByFieldName("name")
			if nameNode == nil {
				// Try package_identifier
				for i := 0; i < int(pkgs[0].ChildCount()); i++ {
					child := pkgs[0].Child(uint(i))
					if child != nil && child.Kind() == "package_identifier" {
						return child.Utf8Text(source)
					}
				}
			} else {
				return nameNode.Utf8Text(source)
			}
		}
	case "python":
		// Python doesn't have package declarations in the same way
		return ""
	}
	return ""
}

func extractFunctions(root *tree_sitter.Node, source []byte, langID string) []FuncInfo {
	var funcs []FuncInfo

	switch langID {
	case "go":
		// Regular functions
		for _, node := range parser.Filter(root, "function_declaration") {
			f := goFuncInfo(node, source, langID)
			funcs = append(funcs, f)
		}
		// Methods
		for _, node := range parser.Filter(root, "method_declaration") {
			f := goFuncInfo(node, source, langID)
			funcs = append(funcs, f)
		}

	case "javascript", "typescript":
		// Function declarations
		for _, node := range parser.Filter(root, "function_declaration") {
			f := jsFuncInfo(node, source, langID)
			funcs = append(funcs, f)
		}
		// Exported functions
		for _, node := range parser.Filter(root, "export_statement") {
			decl := node.NamedChild(0)
			if decl != nil && decl.Kind() == "function_declaration" {
				f := jsFuncInfo(decl, source, langID)
				f.Exported = true
				funcs = append(funcs, f)
			}
		}

	case "python":
		for _, node := range parser.Filter(root, "function_definition") {
			f := pythonFuncInfo(node, source, langID)
			funcs = append(funcs, f)
		}
	}

	return funcs
}

func goFuncInfo(node *tree_sitter.Node, source []byte, langID string) FuncInfo {
	f := FuncInfo{
		StartLine: int(node.StartPosition().Row) + 1,
		EndLine:   int(node.EndPosition().Row) + 1,
		Doc:       docstring.Extract(node, source, langID),
	}

	nameNode := node.ChildByFieldName("name")
	if nameNode != nil {
		f.Name = nameNode.Utf8Text(source)
		f.Exported = len(f.Name) > 0 && f.Name[0] >= 'A' && f.Name[0] <= 'Z'
	}

	// Build signature
	f.Signature = buildGoSignature(node, source)

	// Check for receiver (method)
	if node.Kind() == "method_declaration" {
		recv := node.ChildByFieldName("receiver")
		if recv != nil {
			f.Receiver = recv.Utf8Text(source)
		}
	}

	return f
}

func buildGoSignature(node *tree_sitter.Node, source []byte) string {
	var sig strings.Builder
	sig.WriteString("func ")

	// Receiver for methods
	if node.Kind() == "method_declaration" {
		recv := node.ChildByFieldName("receiver")
		if recv != nil {
			sig.WriteString(recv.Utf8Text(source))
			sig.WriteString(" ")
		}
	}

	name := node.ChildByFieldName("name")
	if name != nil {
		sig.WriteString(name.Utf8Text(source))
	}

	params := node.ChildByFieldName("parameters")
	if params != nil {
		sig.WriteString(params.Utf8Text(source))
	}

	result := node.ChildByFieldName("result")
	if result != nil {
		sig.WriteString(" ")
		sig.WriteString(result.Utf8Text(source))
	}

	return sig.String()
}

func jsFuncInfo(node *tree_sitter.Node, source []byte, langID string) FuncInfo {
	f := FuncInfo{
		StartLine: int(node.StartPosition().Row) + 1,
		EndLine:   int(node.EndPosition().Row) + 1,
		Doc:       docstring.Extract(node, source, langID),
	}

	nameNode := node.ChildByFieldName("name")
	if nameNode != nil {
		f.Name = nameNode.Utf8Text(source)
	}

	// Build signature from first line
	text := node.Utf8Text(source)
	if idx := strings.Index(text, "{"); idx > 0 {
		f.Signature = strings.TrimSpace(text[:idx])
	} else {
		firstLine := text
		if nl := strings.Index(text, "\n"); nl > 0 {
			firstLine = text[:nl]
		}
		f.Signature = strings.TrimSpace(firstLine)
	}

	return f
}

func pythonFuncInfo(node *tree_sitter.Node, source []byte, langID string) FuncInfo {
	f := FuncInfo{
		StartLine: int(node.StartPosition().Row) + 1,
		EndLine:   int(node.EndPosition().Row) + 1,
		Doc:       docstring.Extract(node, source, langID),
	}

	nameNode := node.ChildByFieldName("name")
	if nameNode != nil {
		f.Name = nameNode.Utf8Text(source)
	}

	// Build signature from def line
	text := node.Utf8Text(source)
	if idx := strings.Index(text, ":"); idx > 0 {
		f.Signature = strings.TrimSpace(text[:idx])
	}

	return f
}

func extractTypes(root *tree_sitter.Node, source []byte, langID string) []TypeInfo {
	var types []TypeInfo

	switch langID {
	case "go":
		for _, node := range parser.Filter(root, "type_declaration") {
			for i := 0; i < int(node.NamedChildCount()); i++ {
				spec := node.NamedChild(uint(i))
				if spec == nil {
					continue
				}
				t := TypeInfo{
					StartLine: int(spec.StartPosition().Row) + 1,
					EndLine:   int(spec.EndPosition().Row) + 1,
					Doc:       docstring.Extract(node, source, langID),
				}

				nameNode := spec.ChildByFieldName("name")
				if nameNode != nil {
					t.Name = nameNode.Utf8Text(source)
					t.Exported = len(t.Name) > 0 && t.Name[0] >= 'A' && t.Name[0] <= 'Z'
				}

				typeNode := spec.ChildByFieldName("type")
				if typeNode != nil {
					t.Kind = typeNode.Kind()
					if t.Kind == "struct_type" {
						t.Kind = "struct"
						t.Fields = extractGoStructFields(typeNode, source)
					} else if t.Kind == "interface_type" {
						t.Kind = "interface"
					}
				}

				types = append(types, t)
			}
		}

	case "javascript", "typescript":
		// TS interfaces
		for _, node := range parser.Filter(root, "interface_declaration") {
			t := TypeInfo{
				Kind:      "interface",
				StartLine: int(node.StartPosition().Row) + 1,
				EndLine:   int(node.EndPosition().Row) + 1,
				Doc:       docstring.Extract(node, source, langID),
			}
			nameNode := node.ChildByFieldName("name")
			if nameNode != nil {
				t.Name = nameNode.Utf8Text(source)
			}
			types = append(types, t)
		}
		// TS type aliases
		for _, node := range parser.Filter(root, "type_alias_declaration") {
			t := TypeInfo{
				Kind:      "type_alias",
				StartLine: int(node.StartPosition().Row) + 1,
				EndLine:   int(node.EndPosition().Row) + 1,
			}
			nameNode := node.ChildByFieldName("name")
			if nameNode != nil {
				t.Name = nameNode.Utf8Text(source)
			}
			types = append(types, t)
		}

	case "python":
		for _, node := range parser.Filter(root, "class_definition") {
			t := TypeInfo{
				Kind:      "class",
				StartLine: int(node.StartPosition().Row) + 1,
				EndLine:   int(node.EndPosition().Row) + 1,
				Doc:       docstring.Extract(node, source, langID),
			}
			nameNode := node.ChildByFieldName("name")
			if nameNode != nil {
				t.Name = nameNode.Utf8Text(source)
			}
			types = append(types, t)
		}
	}

	return types
}

func extractGoStructFields(structNode *tree_sitter.Node, source []byte) []FieldInfo {
	var fields []FieldInfo
	fieldList := structNode.ChildByFieldName("fields")
	if fieldList == nil {
		// Try finding field_declaration_list
		for i := 0; i < int(structNode.ChildCount()); i++ {
			child := structNode.Child(uint(i))
			if child != nil && child.Kind() == "field_declaration_list" {
				fieldList = child
				break
			}
		}
	}
	if fieldList == nil {
		return fields
	}

	for i := 0; i < int(fieldList.NamedChildCount()); i++ {
		field := fieldList.NamedChild(uint(i))
		if field == nil || field.Kind() != "field_declaration" {
			continue
		}
		nameNode := field.ChildByFieldName("name")
		typeNode := field.ChildByFieldName("type")
		if nameNode != nil && typeNode != nil {
			fields = append(fields, FieldInfo{
				Name: nameNode.Utf8Text(source),
				Type: typeNode.Utf8Text(source),
			})
		}
	}
	return fields
}

func extractImports(root *tree_sitter.Node, source []byte, langID string) []ImportInfo {
	var imports []ImportInfo

	switch langID {
	case "go":
		for _, node := range parser.Filter(root, "import_declaration") {
			for i := 0; i < int(node.NamedChildCount()); i++ {
				child := node.NamedChild(uint(i))
				if child == nil {
					continue
				}
				if child.Kind() == "import_spec" {
					imp := goImportSpec(child, source)
					imports = append(imports, imp)
				} else if child.Kind() == "import_spec_list" {
					for j := 0; j < int(child.NamedChildCount()); j++ {
						spec := child.NamedChild(uint(j))
						if spec != nil && spec.Kind() == "import_spec" {
							imp := goImportSpec(spec, source)
							imports = append(imports, imp)
						}
					}
				}
			}
		}

	case "javascript", "typescript":
		for _, node := range parser.Filter(root, "import_statement") {
			imp := ImportInfo{
				Line: int(node.StartPosition().Row) + 1,
			}
			srcNode := node.ChildByFieldName("source")
			if srcNode != nil {
				imp.Path = stripQuotes(srcNode.Utf8Text(source))
			}
			imports = append(imports, imp)
		}

	case "python":
		for _, node := range parser.Filter(root, "import_statement") {
			imp := ImportInfo{
				Line: int(node.StartPosition().Row) + 1,
				Path: extractPythonImportPath(node, source),
			}
			imports = append(imports, imp)
		}
		for _, node := range parser.Filter(root, "import_from_statement") {
			imp := ImportInfo{
				Line: int(node.StartPosition().Row) + 1,
				Path: extractPythonImportPath(node, source),
			}
			imports = append(imports, imp)
		}
	}

	return imports
}

func goImportSpec(node *tree_sitter.Node, source []byte) ImportInfo {
	imp := ImportInfo{
		Line: int(node.StartPosition().Row) + 1,
	}
	pathNode := node.ChildByFieldName("path")
	if pathNode != nil {
		imp.Path = stripQuotes(pathNode.Utf8Text(source))
	}
	nameNode := node.ChildByFieldName("name")
	if nameNode != nil {
		imp.Alias = nameNode.Utf8Text(source)
	}
	return imp
}

func extractPythonImportPath(node *tree_sitter.Node, source []byte) string {
	// Get the module name from the import
	for i := 0; i < int(node.NamedChildCount()); i++ {
		child := node.NamedChild(uint(i))
		if child == nil {
			continue
		}
		if child.Kind() == "dotted_name" || child.Kind() == "relative_import" {
			return child.Utf8Text(source)
		}
	}
	// Fallback: get the text after "import" or "from"
	text := node.Utf8Text(source)
	return strings.TrimSpace(text)
}

func extractConstants(root *tree_sitter.Node, source []byte, langID string) []ConstInfo {
	var consts []ConstInfo

	if langID == "go" {
		for _, node := range parser.Filter(root, "const_declaration") {
			for i := 0; i < int(node.NamedChildCount()); i++ {
				spec := node.NamedChild(uint(i))
				if spec == nil || spec.Kind() != "const_spec" {
					continue
				}
				c := ConstInfo{
					StartLine: int(spec.StartPosition().Row) + 1,
				}
				nameNode := spec.ChildByFieldName("name")
				if nameNode != nil {
					c.Name = nameNode.Utf8Text(source)
					c.Exported = len(c.Name) > 0 && c.Name[0] >= 'A' && c.Name[0] <= 'Z'
				}
				valNode := spec.ChildByFieldName("value")
				if valNode != nil {
					c.Value = valNode.Utf8Text(source)
				}
				consts = append(consts, c)
			}
		}
	}

	return consts
}

func stripQuotes(s string) string {
	if len(s) >= 2 {
		if (s[0] == '"' && s[len(s)-1] == '"') || (s[0] == '\'' && s[len(s)-1] == '\'') || (s[0] == '`' && s[len(s)-1] == '`') {
			return s[1 : len(s)-1]
		}
	}
	return s
}

func countLines(source []byte) int {
	return bytes.Count(source, []byte{'\n'}) + 1
}

func generateTags(info *FileInfo, _ string) []string {
	var tags []string
	if info.FunctionCount > 0 {
		tags = append(tags, "has-functions")
	}
	if info.TypeCount > 0 {
		tags = append(tags, "has-types")
	}
	if info.ImportCount > 0 {
		tags = append(tags, "has-imports")
	}
	return tags
}
