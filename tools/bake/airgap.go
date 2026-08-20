package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

const extraImagesFilename = "extra-images.txt"

// Validates the declared airgapImages lockfile against a fresh scan (images
// referenced only OUTSIDE workload `image:` fields) and records them for
// extra-images.txt, which the airgap bundler reads.
func (c *versionCtx) collectHiddenImages() error {
	scanned := difference(c.allImages, c.workloadImages)
	declared := uniqueSorted(c.ver.AirgapImages)
	if !slices.Equal(declared, scanned) {
		return c.lockfileMismatch(scanned)
	}
	c.hiddenImages = scanned
	return nil
}

// Records the hidden images in helmrelease/extra-images.txt so the airgap
// bundler mirrors them; with none, any stale file is removed.
func (c *versionCtx) writeExtraImages() error {
	path := filepath.Join(c.manifestsDir, extraImagesFilename)
	var existing []string
	if data, err := os.ReadFile(filepath.Clean(path)); err == nil {
		existing = uniqueSorted(strings.Split(string(data), "\n"))
	} else if !os.IsNotExist(err) {
		return err
	}

	merged := uniqueSorted(append(existing, c.hiddenImages...))
	if len(merged) == 0 {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}

	fmt.Printf("==> Writing %d merged extra image(s) to %s:\n", len(merged), c.rel(path))
	printIndented(merged)
	if err := os.MkdirAll(c.manifestsDir, dirMode); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Join(merged, "\n")+"\n"), fileMode)
}

// Reports a copy-paste-ready airgapImages block and aborts.
func (c *versionCtx) lockfileMismatch(scanned []string) error {
	var b strings.Builder
	fmt.Fprintf(&b, "airgap image lockfile mismatch for %s %s.\n", c.app, c.ver.Version)
	b.WriteString("  Images referenced only OUTSIDE workload 'image:' fields must be declared\n")
	fmt.Fprintf(&b, "  verbatim under this version's airgapImages in %s so the airgap bundle\n", c.configPath)
	b.WriteString("  mirrors them. The current render scans:\n\n")
	b.WriteString("    airgapImages:\n")
	if len(scanned) == 0 {
		b.WriteString("      [] # none scanned; remove the airgapImages key\n")
	}
	for _, s := range scanned {
		fmt.Fprintf(&b, "      - %s\n", s)
	}
	fmt.Fprintf(&b, "\n  Update %s to match exactly, then re-run.", c.configPath)
	return fmt.Errorf("%s", b.String())
}
