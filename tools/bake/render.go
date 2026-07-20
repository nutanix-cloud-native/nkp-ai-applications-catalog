package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// These patterns are best-effort heuristics, not full parsers: they may miss
// unusual refs or over-match (e.g. a registry-like URL in a comment).
var (
	// value after an `image:` key, e.g. "image: nginx:1.25" -> "nginx:1.25".
	imageFieldRe = regexp.MustCompile(`image:[ \t]*(\S+)`)
	// any "<known-registry>/path[:tag]" token anywhere in the text, so we also
	// catch images buried in env/args/ConfigMap values.
	registryRefRe = regexp.MustCompile(
		`(?:ghcr\.io|gcr\.io|quay\.io|docker\.io|registry\.k8s\.io|mcr\.microsoft\.com)` +
			`/[a-zA-Z0-9._/-]+(?::[a-zA-Z0-9._-]+)?`,
	)
)

// Shallow-clones the pinned ref into the per-version workspace.
func (c *versionCtx) cloneUpstream() error {
	fmt.Printf("==> [%s %s] Cloning upstream repository...\n", c.app, c.ver.Version)
	if err := os.RemoveAll(c.cloneDir); err != nil {
		return err
	}
	if err := os.MkdirAll(c.workDir, dirMode); err != nil {
		return err
	}
	return quiet("git", "clone", "--depth", "1", "--branch", c.ver.Ref, c.repo, c.cloneDir)
}

// Flattens the remote Kustomize structure into one raw manifest, bypassing
// Flux's inability to resolve parent ("../") paths in air-gaps.
// LoadRestrictionsRootOnly matches the airgap parser's strict requirements.
func (c *versionCtx) renderOverlays() error {
	var b strings.Builder
	for _, overlay := range c.ver.Overlays {
		fmt.Printf("==> Rendering overlay: %s\n", overlay)
		out, err := capture("kustomize", "build",
			"--load-restrictor", "LoadRestrictionsRootOnly",
			filepath.Join(c.cloneDir, overlay))
		if err != nil {
			return err
		}
		if b.Len() > 0 {
			b.WriteString("\n---\n")
		}
		b.Write(out)
	}
	c.rawManifest = b.String()
	return nil
}

// Populates two lists from the raw manifest:
//   - workloadImages: values of real `image:` fields (what pods run).
//   - allImages:      those plus every registry-qualified ref found anywhere
//     (env/args/ConfigMap values) — the ones the airgap scanner would miss.
func (c *versionCtx) discoverImages() {
	c.workloadImages = imageFieldValues(c.rawManifest)
	all := append([]string{}, c.workloadImages...)
	all = append(all, registryRefRe.FindAllString(c.rawManifest, -1)...)
	c.allImages = uniqueSorted(all)
}

func imageFieldValues(manifest string) []string {
	matches := imageFieldRe.FindAllStringSubmatch(manifest, -1)
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		out = append(out, strings.Trim(m[1], `"`))
	}
	return uniqueSorted(out)
}

// Trims, drops blanks and duplicates, and sorts (matching the shell's `sort -u`).
func uniqueSorted(in []string) []string {
	out := make([]string, 0, len(in))
	for _, s := range in {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	slices.Sort(out)
	return slices.Compact(out)
}
