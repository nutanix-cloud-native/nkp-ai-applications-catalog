package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Permission bits for the directories and files bake writes
// gosec's G301/G306 reject the usual 0o755/0o644 as too permissive.
const (
	dirMode  os.FileMode = 0o750
	fileMode os.FileMode = 0o600
)

// Returns the sorted-unique members of a that are not in b.
func difference(a, b []string) []string {
	inB := make(map[string]bool, len(b))
	for _, s := range b {
		inB[s] = true
	}
	var out []string
	for _, s := range a {
		if !inB[s] {
			out = append(out, s)
		}
	}
	return uniqueSorted(out)
}

func printIndented(lines []string) {
	for _, l := range lines {
		fmt.Printf("      %s\n", l)
	}
}

// Makes a path repo-root-relative for tidy log output.
func (c *versionCtx) rel(path string) string {
	if r, err := filepath.Rel(c.repoRoot, path); err == nil {
		return r
	}
	return path
}

// Counts top-level resources in a manifest (lines starting `kind:`).
func countKinds(manifest string) int {
	n := 0
	for _, line := range strings.Split(manifest, "\n") {
		if strings.HasPrefix(line, "kind:") {
			n++
		}
	}
	return n
}
