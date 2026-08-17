package suites

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
	"k8s.io/apimachinery/pkg/runtime/schema"

	"github.com/nutanix-cloud-native/nkp-ai-applications-catalog/apptests/harness"
)

const (
	certManagerManifestURL = "https://github.com/cert-manager/cert-manager/releases/download/v1.19.3/cert-manager.yaml"
	//nolint:lll // upstream Istio CRD bundle URL cannot be shortened.
	istioCRDsManifestURL    = "https://raw.githubusercontent.com/istio/istio/1.25.0/manifests/charts/base/files/crd-all.gen.yaml"
	nkpDexStubsManifestPath = "testdata/nkp-dex-stubs.yaml"
)

var deploymentGVK = schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"}

// dependencyProvisioners installs a lightweight stand-in on Kind for each
// platform dependency an app names in its metadata requiredDependencies.
var dependencyProvisioners = map[string]func(context.Context) error{
	"cert-manager": provisionCertManager,
	"istio-helm":   provisionIstioCRDs,
	"dex":          provisionNKPDexStubs,
}

// provisionDependencies installs every dependency the app declares in its
// metadata, so metadata.yaml is the single source of truth shared by the Helm
// and Kustomize suites.
func provisionDependencies(ctx context.Context, appName string) error {
	deps, err := requiredDependencies(appName)
	if err != nil {
		return err
	}
	for _, dep := range deps {
		provision, ok := dependencyProvisioners[dep]
		if !ok {
			return fmt.Errorf(
				"app %q requires %q, which has no provisioner in dependencyProvisioners", appName, dep,
			)
		}
		if err := provision(ctx); err != nil {
			return fmt.Errorf("provisioning %q for %q: %w", dep, appName, err)
		}
	}
	return nil
}

func requiredDependencies(appName string) ([]string, error) {
	path, err := metadataPath(appName, harness.Default.AppVersion())
	if err != nil {
		return nil, err
	}

	// #nosec G304 -- path is built from the fixed repo layout and validated app inputs.
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var metadata struct {
		RequiredDependencies []string `yaml:"requiredDependencies"`
	}
	if err := yaml.Unmarshal(content, &metadata); err != nil {
		return nil, err
	}
	return metadata.RequiredDependencies, nil
}

// metadataPath resolves applications/<app>/<version>/metadata.yaml.
func metadataPath(appName, version string) (string, error) {
	if version == "" {
		return "", fmt.Errorf("app version is required to locate metadata for %q", appName)
	}
	appsDir, err := harness.ApplicationsDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(appsDir, appName, version, "metadata.yaml"), nil
}

func provisionCertManager(ctx context.Context) error {
	if err := applyRemoteManifest(ctx, certManagerManifestURL); err != nil {
		return err
	}
	for _, deployment := range []string{"cert-manager", "cert-manager-webhook", "cert-manager-cainjector"} {
		if err := harness.WaitForCondition(
			ctx, harness.Default.Client(), deploymentGVK,
			"cert-manager", deployment, "Available", 5*time.Minute, 2*time.Second,
		); err != nil {
			return fmt.Errorf("waiting for %s to become Available: %w", deployment, err)
		}
	}
	return nil
}

func provisionIstioCRDs(ctx context.Context) error {
	return applyRemoteManifest(ctx, istioCRDsManifestURL)
}

func provisionNKPDexStubs(ctx context.Context) error {
	if err := applyManifestFile(ctx, nkpDexStubsManifestPath); err != nil {
		return err
	}
	return harness.WaitForCondition(
		ctx, harness.Default.Client(), deploymentGVK,
		"kubeflow", "dex-mock", "Available", 5*time.Minute, 2*time.Second,
	)
}

// applyRemoteManifest fetches a multi-doc YAML manifest and server-side applies
// it through the harness, so it lands on whichever cluster the backend selected.
func applyRemoteManifest(ctx context.Context, url string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("fetching %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("fetching %s: unexpected status %s", url, resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("reading %s: %w", url, err)
	}
	return harness.Default.ApplyYAML(ctx, data)
}

func applyManifestFile(ctx context.Context, relativePath string) error {
	// Run from apptests/ during tests; fixture path is relative to that root.
	// #nosec G304 -- path is a fixed constant controlled in test code.
	data, err := os.ReadFile(relativePath)
	if err != nil {
		return fmt.Errorf("reading %s: %w", relativePath, err)
	}
	return harness.Default.ApplyYAML(ctx, data)
}
