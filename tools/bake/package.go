package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// Writes the packaging kustomization, runs `kustomize build`, and (only with
// --registry) rewrites image refs kustomize can't reach.
func (c *versionCtx) packageAndRewrite() error {
	if err := os.RemoveAll(c.pkgDir); err != nil {
		return err
	}
	if err := os.MkdirAll(c.pkgDir, dirMode); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(c.pkgDir, "resources.yaml"), []byte(c.rawManifest), fileMode); err != nil {
		return err
	}
	kustomization, err := c.kustomizationFile()
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(c.pkgDir, "kustomization.yaml"), []byte(kustomization), fileMode); err != nil {
		return err
	}
	out, err := capture("kustomize", "build", c.pkgDir)
	if err != nil {
		return err
	}
	c.rendered = string(out)
	if c.registry != "" {
		c.rewriteHiddenRefs()
	}
	return os.WriteFile(c.renderedPath, []byte(c.rendered), fileMode)
}

// The packaging kustomization we hand to `kustomize build`: the raw resources,
// an optional namespace transformer, staged patches, and (with --registry) an
// images: block that repoints refs onto the rehost registry.
type kustomization struct {
	APIVersion string      `yaml:"apiVersion"`
	Kind       string      `yaml:"kind"`
	Namespace  string      `yaml:"namespace,omitempty"`
	Resources  []string    `yaml:"resources"`
	Patches    []kustPatch `yaml:"patches,omitempty"`
	Images     []kustImage `yaml:"images,omitempty"`
}

type kustPatch struct {
	Path   string      `yaml:"path"`
	Target *kustTarget `yaml:"target,omitempty"`
}

type kustTarget struct {
	Kind string `yaml:"kind"`
	Name string `yaml:"name"`
}

type kustImage struct {
	Name    string `yaml:"name"`
	NewName string `yaml:"newName"`
}

func (c *versionCtx) kustomizationFile() (string, error) {
	k := kustomization{
		APIVersion: "kustomize.config.k8s.io/v1beta1",
		Kind:       "Kustomization",
		Namespace:  c.ver.Namespace,
		Resources:  []string{"resources.yaml"},
	}
	patches, err := c.stagePatches()
	if err != nil {
		return "", err
	}
	k.Patches = patches

	if c.registry != "" {
		for _, image := range c.workloadImages {
			name := stripTag(image)
			k.Images = append(k.Images, kustImage{Name: name, NewName: c.registryImagePath(name)})
		}
	}

	out, err := encodeYAML(k)
	return string(out), err
}

// Copies each patch into the packaging dir (RootOnly load-restrictor forbids
// paths outside the root) and returns its `patches:` entry with a kind+name
// target so it survives the namespace transformer.
func (c *versionCtx) stagePatches() ([]kustPatch, error) {
	var patches []kustPatch
	for _, patch := range c.ver.Patches {
		base := filepath.Base(patch)
		//nolint:gosec // patch paths come from the bake config, resolved against the repo root
		data, err := os.ReadFile(filepath.Join(c.repoRoot, patch))
		if err != nil {
			return nil, err
		}
		//nolint:gosec // base is filepath.Base of a configured patch, written into our temp pkg dir
		if err := os.WriteFile(filepath.Join(c.pkgDir, base), data, fileMode); err != nil {
			return nil, err
		}
		entry := kustPatch{Path: base}
		if kind, name := patchTarget(data); kind != "" && name != "" {
			entry.Target = &kustTarget{Kind: kind, Name: name}
		}
		patches = append(patches, entry)
	}
	return patches, nil
}

func patchTarget(data []byte) (kind, name string) {
	var doc struct {
		Kind     string `yaml:"kind"`
		Metadata struct {
			Name string `yaml:"name"`
		} `yaml:"metadata"`
	}
	_ = yaml.Unmarshal(data, &doc)
	return doc.Kind, doc.Metadata.Name
}

// Repoints image refs kustomize's images: transformer can't see (env vars,
// args, ConfigMap values), only at real word boundaries so "gcr.io/foo" is
// rewritten while "notgcr.io/foo" is not.
// Example: 'value: "gcr.io/foo:v1"' -> 'value: "myreg/gcr.io/foo:v1"'.
func (c *versionCtx) rewriteHiddenRefs() {
	for _, image := range c.allImages {
		name := stripTag(image)
		// Only refs with an explicit registry host (a dot before the first slash);
		// bare Docker Hub names were already handled by the images: transformer.
		if !hasRegistryHost(name) {
			continue
		}
		re := regexp.MustCompile(`(?m)(^|[^A-Za-z0-9._/@-])` + regexp.QuoteMeta(name) + `([:@"' )]|$)`)
		c.rendered = re.ReplaceAllString(c.rendered, "${1}"+c.registryImagePath(name)+"${2}")
	}
}

// Copies every referenced image onto the rehost registry.
func (c *versionCtx) mirrorImages() error {
	if !c.mirror {
		return nil
	}
	if c.registry == "" {
		return fmt.Errorf("--mirror-images requires --registry")
	}
	fmt.Printf("==> Mirroring images to %s\n", c.registry)
	for _, image := range c.allImages {
		target := c.registryImagePath(image)
		fmt.Printf("    Copying: %s -> %s\n", image, target)
		if err := stream("crane", "copy", image, target); err != nil {
			return err
		}
	}
	return nil
}

// Rewrites one ref onto the rehost registry, preserving its repo path. Docker
// Hub is the awkward case: "busybox" or "argoproj/argoexec" carry no host, and
// Docker implicitly expands a bare name to "library/<name>".
func (c *versionCtx) registryImagePath(image string) string {
	firstPart := image
	if i := strings.Index(image, "/"); i >= 0 {
		firstPart = image[:i]
	}
	var path string
	switch {
	case strings.Contains(firstPart, ".") || strings.Contains(firstPart, ":") || firstPart == "localhost":
		// explicit registry host: drop it, keep the rest
		if i := strings.Index(image, "/"); i >= 0 {
			path = image[i+1:]
		} else {
			path = image
		}
	case strings.Contains(image, "/"):
		path = image // Docker Hub "user/repo": keep as-is
	default:
		path = "library/" + image // Docker Hub bare name
	}
	return c.registry + "/" + path
}

// Drops a trailing ":tag" (from the last colon) while keeping any "host:port".
// Mirrors bash ${image%:*}.
func stripTag(image string) string {
	if i := strings.LastIndex(image, ":"); i >= 0 {
		return image[:i]
	}
	return image
}

// Reports whether the ref has an explicit registry host: a dot before the first
// slash (e.g. "gcr.io/foo"). Mirrors bash glob *.*/*.
func hasRegistryHost(name string) bool {
	i := strings.Index(name, "/")
	return i >= 0 && strings.Contains(name[:i], ".")
}
