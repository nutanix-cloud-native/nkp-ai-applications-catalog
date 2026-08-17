package suites

import (
	"fmt"
	"testing"

	"github.com/nutanix-cloud-native/nkp-ai-applications-catalog/apptests/harness"
)

// enabledApps deploy via a HelmRelease and get the generic install + upgrade
// template test (registerDefaultTestsWithDependencies). Add a HelmRelease app
// here to enable its E2E test.
var enabledApps = []string{
	"milvus-operator",
	"kueue",
	"kai-scheduler",
	"jupyterhub",
	"slurm-operator",
	"ollama",
	"kubeflow-platform",
}

// customTestApps deploy via Flux GitRepository + Kustomization instead of a
// HelmRelease. They run through the shared Kustomize suite
// (flux_kustomize_apps_test.go); platform dependencies come from each app's
// metadata.yaml. Add a Flux-Kustomize app here only once it is graduated from
// parking-lot/drafts-repo into applications/, so its E2E test and CI matrix
// detection can resolve applications/<app>.
var customTestApps = []string{
	"kubeflow-central-dashboard",
	"kubeflow-pipelines",
}

//nolint:gochecknoinits // init required for test registration before suite runs
func init() {
	harness.InitSuite()
	for _, app := range enabledApps {
		registerDefaultTestsWithDependencies(app)
	}

	// Guard against an app being both auto-registered and custom-registered
	enabled := make(map[string]bool, len(enabledApps))
	for _, app := range enabledApps {
		enabled[app] = true
	}
	for _, app := range customTestApps {
		if enabled[app] {
			panic(fmt.Sprintf("app %q is listed in both enabledApps and customTestApps", app))
		}
	}
}

func TestApplications(t *testing.T) { harness.RunSuite(t) }
