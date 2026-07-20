// Command bake renders complex Kustomize apps into a single self-contained
// manifest (enabling air-gapped deployment of apps like Kubeflow that rely on
// remote bases Flux's load-restrictor blocks) and, for chart-enabled apps, a
// parameterized Helm chart that gives them a configOverrides surface.
//
// It reads scripts/bake-apps.yaml and shells out to git (clone the pinned ref),
// kustomize (render overlays), and — only for --mirror-images — crane. Run it
// from the repo root:
//
//	go run ./tools/bake --app kubeflow-pipelines
//	go run ./tools/bake --app kubeflow-pipelines --version 2.15.0
//	go run ./tools/bake --all                       # every configured app
//	go run ./tools/bake --app kubeflow-pipelines --render-only
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

type options struct {
	app        string
	version    string
	configPath string
	registry   string
	mirror     bool
	renderOnly bool
	all        bool
}

// versionCtx carries per-app+version state through the pipeline stages, which
// run in this order (see process): cloneUpstream -> renderOverlays ->
// discoverImages -> collectHiddenImages -> packageAndRewrite -> mirrorImages ->
// generateChart -> writeExtraImages.
type versionCtx struct {
	// CLI-derived inputs.
	repoRoot   string
	configPath string
	registry   string
	mirror     bool
	renderOnly bool

	// App + version being baked.
	app  string
	repo string
	ver  Version

	// Per-version workspace paths.
	workDir      string
	cloneDir     string
	pkgDir       string
	renderedPath string
	manifestsDir string

	// Pipeline state, filled in as stages run.
	rawManifest    string   // renderOverlays output
	rendered       string   // packageAndRewrite output
	workloadImages []string // values of real image: fields
	allImages      []string // workloadImages + refs hidden in env/args/ConfigMaps
	hiddenImages   []string // refs only found outside image: fields
}

func newVersionCtx(repoRoot string, opts options, app string, appCfg App, ver *Version) *versionCtx {
	workDir := filepath.Join(repoRoot, ".tmp", "bake-"+app+"-"+ver.Version)
	return &versionCtx{
		repoRoot:     repoRoot,
		configPath:   opts.configPath,
		registry:     opts.registry,
		mirror:       opts.mirror,
		renderOnly:   opts.renderOnly,
		app:          app,
		repo:         appCfg.Repo,
		ver:          *ver,
		workDir:      workDir,
		cloneDir:     filepath.Join(workDir, "upstream"),
		pkgDir:       filepath.Join(workDir, "package"),
		renderedPath: filepath.Join(workDir, app+".yaml"),
		manifestsDir: filepath.Join(repoRoot, "applications", app, ver.Version, "helmrelease"),
	}
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: "+err.Error())
		os.Exit(1)
	}
}

func run() error {
	opts := parseFlags()
	for _, tool := range []string{"kustomize", "git"} {
		if !have(tool) {
			return fmt.Errorf("%s is required", tool)
		}
	}
	if opts.mirror && !have("crane") {
		return fmt.Errorf("crane is required for --mirror-images")
	}
	repoRoot, err := findRepoRoot()
	if err != nil {
		return err
	}
	// Resolve a relative --config against the repo root so the tool works no
	// matter which directory `go run` is invoked from.
	if !filepath.IsAbs(opts.configPath) {
		opts.configPath = filepath.Join(repoRoot, opts.configPath)
	}
	cfg, err := loadConfig(opts.configPath)
	if err != nil {
		return err
	}

	apps, err := selectApps(cfg, opts)
	if err != nil {
		return err
	}
	for _, app := range apps {
		if err := bakeApp(repoRoot, opts, app, cfg.Apps[app]); err != nil {
			return err
		}
	}
	return nil
}

// Walks up from the working directory to the catalog repo root, identified by
// scripts/bake-apps.yaml (or a .git dir as a fallback). This lets the justfile
// invoke the tool from inside its own module (tools/bake) while all outputs
// still land under the repo root.
func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "scripts", "bake-apps.yaml")); err == nil {
			return dir, nil
		}
		if fi, err := os.Stat(filepath.Join(dir, ".git")); err == nil && fi.IsDir() {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("could not locate repo root (no scripts/bake-apps.yaml or .git found above %s)", dir)
		}
		dir = parent
	}
}

func parseFlags() options {
	var o options
	flag.StringVar(&o.app, "app", "", "app to bake (required unless --all)")
	flag.StringVar(&o.version, "version", "", "only this version (default: all configured)")
	flag.StringVar(&o.configPath, "config", "scripts/bake-apps.yaml", "bake config file")
	flag.StringVar(&o.registry, "registry", "", "rehost registry for image refs")
	flag.BoolVar(&o.mirror, "mirror-images", false, "mirror images to --registry (needs crane)")
	flag.BoolVar(&o.renderOnly, "render-only", false, "render + summarize, don't write artifacts")
	flag.BoolVar(&o.all, "all", false, "bake every app in the config (for drift checks)")
	flag.Parse()
	o.registry = strings.TrimRight(o.registry, "/")
	return o
}

func selectApps(cfg *Config, opts options) ([]string, error) {
	if opts.all {
		names := make([]string, 0, len(cfg.Apps))
		for name := range cfg.Apps {
			names = append(names, name)
		}
		slices.Sort(names)
		return names, nil
	}
	if opts.app == "" {
		return nil, fmt.Errorf("--app is required (or use --all)")
	}
	if _, ok := cfg.Apps[opts.app]; !ok {
		return nil, fmt.Errorf("app %q is not configured in %s", opts.app, opts.configPath)
	}
	return []string{opts.app}, nil
}

func bakeApp(repoRoot string, opts options, app string, appCfg App) error {
	if appCfg.Repo == "" {
		return fmt.Errorf("app %q is missing a repo in %s", app, opts.configPath)
	}
	versions := appCfg.Versions
	if opts.version != "" {
		ver, ok := findVersion(appCfg, opts.version)
		if !ok {
			return fmt.Errorf("%s has no version %q in %s", app, opts.version, opts.configPath)
		}
		versions = []Version{ver}
	}
	if len(versions) == 0 {
		return fmt.Errorf("%s has no versions in %s", app, opts.configPath)
	}
	for i := range versions {
		if err := newVersionCtx(repoRoot, opts, app, appCfg, &versions[i]).process(); err != nil {
			return fmt.Errorf("%s %s: %w", app, versions[i].Version, err)
		}
	}
	return nil
}

func findVersion(appCfg App, version string) (Version, bool) {
	for i := range appCfg.Versions {
		if appCfg.Versions[i].Version == version {
			return appCfg.Versions[i], true
		}
	}
	return Version{}, false
}
