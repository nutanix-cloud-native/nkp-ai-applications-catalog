package main

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config is scripts/bake-apps.yaml: apps that lack a usable upstream chart, which
// bake renders from their upstream Kustomize overlays. These types (with their
// yaml tags and field comments) are the schema for that file.
type Config struct {
	Apps map[string]App `yaml:"apps"`
}

type App struct {
	Repo     string    `yaml:"repo"` // upstream git repository
	Versions []Version `yaml:"versions"`
}

type Version struct {
	Version      string   `yaml:"version"`      // catalog version (dir under applications/<app>/)
	Ref          string   `yaml:"ref"`          // pinned upstream git tag or commit
	Overlays     []string `yaml:"overlays"`     // kustomize overlay paths to render, in order
	AirgapImages []string `yaml:"airgapImages"` // images referenced only outside image: fields
	Namespace    string   `yaml:"namespace"`    // bake-time kustomize namespace for split-namespace apps
	Patches      []string `yaml:"patches"`      // repo-relative patches applied at bake time
	Chart        *Chart   `yaml:"chart"`        // chart to generate (required; baked apps ship as charts)
}

// Chart is the generated Helm chart under charts/<app>/, which gives a baked app
// a configOverrides surface.
type Chart struct {
	Version    string     `yaml:"version"`    // Chart.yaml version (default: catalog version)
	AppVersion string     `yaml:"appVersion"` // Chart.yaml appVersion (default: upstream ref)
	Workloads  []Workload `yaml:"workloads"`  // workloads exposed as tunable values
	Overlay    *Overlay   `yaml:"overlay"`    // hand-authored additions layered onto the generated chart
}

// Overlay layers hand-authored content onto the generated chart so `just bake`
// reproduces it deterministically and the drift check stays honest. It covers
// the rare integration bits that can't be derived from upstream, such as a
// dashboard externalLink helper.
type Overlay struct {
	Templates  []string    `yaml:"templates"`  // repo-relative files copied verbatim into templates/
	Injections []Injection `yaml:"injections"` // literal find/replace applied to the generated template
}

// Injection is a literal find/replace applied to the generated template; replace
// may contain Helm syntax (it is applied after placeholder expansion).
type Injection struct {
	Find    string `yaml:"find"`
	Replace string `yaml:"replace"`
}

// Workload is one workload whose resources/replicas/scheduling become tunable
// values in the generated chart.
type Workload struct {
	Name      string `yaml:"name"`      // metadata.name of the workload
	Kind      string `yaml:"kind"`      // workload kind (default: Deployment)
	Container string `yaml:"container"` // container to tune (default: the workload name)
}

// Defaults an unset kind to Deployment.
func (w Workload) KindOrDefault() string {
	if w.Kind == "" {
		return "Deployment"
	}
	return w.Kind
}

// Defaults an unset container name to the workload name.
func (w Workload) ContainerOrDefault() string {
	if w.Container == "" {
		return w.Name
	}
	return w.Container
}

func loadConfig(path string) (*Config, error) {
	//nolint:gosec // path is the bake config file, resolved against the repo root, not user input
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	return &cfg, nil
}
