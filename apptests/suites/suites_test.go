package suites

import (
	"testing"

	"github.com/mesosphere/kommander-applications/apptests/catalog"
)

// skipApps are excluded from auto-registered E2E tests; every other app under
// applications/ gets a default install + upgrade test.
var skipApps = []string{
	// TODO: Flux Kustomization apps. Only HelmRelease is asserted currently.
	"katib", "kubeflow-central-dashboard", "kubeflow-model-registry",
	"kubeflow-pipelines", "spark-operator", "tensorboard-controller", "training-operator",
	// TODO: need dependencies
	"agentgateway", "demo-full-rag",
	// not implemented yet
	"kueue",
	"amd-gpu-operator", "amd-network-operator",
	// needs GPU / AMD device hardware
	"vllm", "amd-device-metrics-exporter",
}

//nolint:gochecknoinits // init required for test registration before suite runs
func init() {
	catalog.InitSuite()
	skip := make(map[string]bool, len(skipApps))
	for _, a := range skipApps {
		skip[a] = true
	}
	// repoRoot is two levels up from apptests/suites/.
	catalog.ScanAndRegister("../..", skip)
}

func TestApplications(t *testing.T) { catalog.RunSuite(t) }
