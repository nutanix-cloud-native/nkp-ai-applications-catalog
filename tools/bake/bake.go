package main

import "fmt"

// Prints the --render-only summary.
func (c *versionCtx) printDryRun() {
	fmt.Printf("==> Dry-run complete. Manifest rendered at: %s\n", c.renderedPath)
	fmt.Println("    Images:")
	printIndented(c.allImages)
}

// Runs one app+version end to end. The stage order mirrors the pipeline
// documented on versionCtx.
func (c *versionCtx) process() error {
	if c.ver.Ref == "" {
		return fmt.Errorf("version %q is missing a ref", c.ver.Version)
	}
	if len(c.ver.Overlays) == 0 {
		return fmt.Errorf("version %q has no overlays listed", c.ver.Version)
	}
	if err := c.cloneUpstream(); err != nil {
		return err
	}
	if err := c.renderOverlays(); err != nil {
		return err
	}
	c.discoverImages()
	if err := c.collectHiddenImages(); err != nil {
		return err
	}
	if err := c.packageAndRewrite(); err != nil {
		return err
	}
	if err := c.mirrorImages(); err != nil {
		return err
	}

	if c.renderOnly {
		c.printDryRun()
		return nil
	}

	if c.ver.Chart == nil {
		return fmt.Errorf("version %q has no chart block; baked apps must be packaged as charts", c.ver.Version)
	}
	if err := c.generateChart(); err != nil {
		return err
	}
	return c.writeExtraImages()
}
