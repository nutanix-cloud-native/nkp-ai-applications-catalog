package main

import (
	"bytes"
	"errors"
	"io"
	"strings"

	"gopkg.in/yaml.v3"
)

// Helpers for editing YAML as a *yaml.Node tree — the parse tree that
// gopkg.in/yaml.v3 produces for a document. Editing the tree in place (instead
// of decoding into structs and re-encoding) lets us change a handful of fields
// while leaving every other key, its order, and its formatting untouched, so
// the generated chart stays a faithful copy of the baked manifest.

// YAML core-schema tags used when building nodes by hand.
const (
	strTag = "!!str"
	intTag = "!!int"
)

// Encodes a node with the standard 2-space indent.
func encodeYAML(node any) ([]byte, error) {
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(node); err != nil {
		return nil, err
	}
	if err := enc.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// Splits a multi-document manifest into one node per document, preserving
// order, comments, and key ordering.
func splitDocs(manifest string) ([]*yaml.Node, error) {
	dec := yaml.NewDecoder(strings.NewReader(manifest))
	var docs []*yaml.Node
	for {
		var n yaml.Node
		err := dec.Decode(&n)
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
		docs = append(docs, &n)
	}
	return docs, nil
}

// Joins document nodes back into a `---`-separated manifest.
func joinDocs(docs []*yaml.Node) (string, error) {
	var b strings.Builder
	for i, doc := range docs {
		if i > 0 {
			b.WriteString("---\n")
		}
		out, err := encodeYAML(doc)
		if err != nil {
			return "", err
		}
		b.Write(out)
	}
	return b.String(), nil
}

// The next four constructors assemble a values.yaml mapping as an explicit node
// tree. Building it by hand (rather than from a Go map) keeps keys in a fixed
// order, which a Go map's randomized iteration would not.

// Appends a key/value pair to a mapping node.
func addPair(m *yaml.Node, key string, value *yaml.Node) {
	m.Content = append(m.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: strTag, Value: key}, value)
}

// Builds an integer scalar node from its string form.
func intNode(v string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: intTag, Value: v}
}

// Builds an empty flow-style mapping ("{}").
func emptyMap() *yaml.Node {
	return &yaml.Node{Kind: yaml.MappingNode, Style: yaml.FlowStyle}
}

// Builds an empty flow-style sequence ("[]").
func emptySeq() *yaml.Node {
	return &yaml.Node{Kind: yaml.SequenceNode, Style: yaml.FlowStyle}
}

// Returns a document's top-level mapping node.
func root(doc *yaml.Node) *yaml.Node {
	if doc.Kind == yaml.DocumentNode && len(doc.Content) > 0 {
		return doc.Content[0]
	}
	return doc
}

// Returns the value node for key in a mapping, or nil.
func mapValue(m *yaml.Node, key string) *yaml.Node {
	if m == nil || m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}

// Removes key (and its value) from a mapping.
func mapDelete(m *yaml.Node, key string) {
	if m == nil || m.Kind != yaml.MappingNode {
		return
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			m.Content = append(m.Content[:i], m.Content[i+2:]...)
			return
		}
	}
}

// Appends a key/value string pair to a mapping.
func mapSetString(m *yaml.Node, key, value string) {
	m.Content = append(m.Content,
		&yaml.Node{Kind: yaml.ScalarNode, Tag: strTag, Value: key},
		&yaml.Node{Kind: yaml.ScalarNode, Tag: strTag, Value: value},
	)
}

// Reports whether a document's root matches kind/name.
func isWorkload(r *yaml.Node, kind, name string) bool {
	k := mapValue(r, "kind")
	md := mapValue(r, "metadata")
	n := mapValue(md, "name")
	return k != nil && k.Value == kind && n != nil && n.Value == name
}

// Returns .spec.template.spec of a workload root.
func podSpec(r *yaml.Node) *yaml.Node {
	return mapValue(mapValue(mapValue(r, "spec"), "template"), "spec")
}

// Returns the named container from a pod spec's containers list.
func container(pod *yaml.Node, name string) *yaml.Node {
	list := mapValue(pod, "containers")
	if list == nil || list.Kind != yaml.SequenceNode {
		return nil
	}
	for _, c := range list.Content {
		if n := mapValue(c, "name"); n != nil && n.Value == name {
			return c
		}
	}
	return nil
}
