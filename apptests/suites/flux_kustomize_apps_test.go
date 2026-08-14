package suites

// Apps deployed via Flux GitRepository + Kustomization (rather than a
// HelmRelease) share this generic suite. Each installs, then its Flux source
// and Kustomization must reach Ready. Platform dependencies (Istio,
// cert-manager, ...) are provisioned from the app's metadata (see
// dependencies.go). The app list is customTestApps in suites_test.go.

import (
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"k8s.io/apimachinery/pkg/runtime/schema"

	"github.com/nutanix-cloud-native/nkp-ai-applications-catalog/apptests/harness"
)

const appNamespace = "default"

var (
	gitRepositoryGVK = schema.GroupVersionKind{
		Group: "source.toolkit.fluxcd.io", Version: "v1", Kind: "GitRepository",
	}
	kustomizationGVK = schema.GroupVersionKind{
		Group: "kustomize.toolkit.fluxcd.io", Version: "v1", Kind: "Kustomization",
	}
	// deploymentGVK is declared in dependencies.go and reused here.
)

// bakedReadiness names the workloads that signal a baked-manifest app is up.
type bakedReadiness struct {
	namespace   string
	deployments []string
}

// bakedManifestApps apply manifests directly from helmrelease/ without Flux sources.
// Readiness is asserted on core workloads; ml-pipeline requires mysql/object store.
var bakedManifestApps = map[string]bakedReadiness{
	"kubeflow-pipelines": {
		namespace:   "kubeflow",
		deployments: []string{"mysql", "ml-pipeline", "ml-pipeline-ui"},
	},
}

//nolint:gochecknoinits // init required for test registration before suite runs
func init() {
	for _, app := range customTestApps {
		registerKustomizeApp(app)
	}
}

func registerKustomizeApp(appName string) {
	Describe(appName+" Tests", Label(appName), func() {
		Describe("Installing "+appName, Ordered, Label("install"), func() {
			BeforeAll(func() {
				Expect(harness.Default.SetupCluster(harness.Default.Context())).To(Succeed())
				Expect(provisionDependencies(harness.Default.Context(), appName)).To(Succeed())
			})

			AfterAll(func() {
				Expect(harness.Default.TeardownCluster(harness.Default.Context())).To(Succeed())
			})

			It("should install successfully with its declared dependencies", func() {
				installAppAndWait(appName)
			})
		})
	})
}

// installAppAndWait installs the app and asserts its success signal: for
// baked-manifest apps that is the core workloads becoming Available; for the
// rest it is the Flux source + Kustomization reaching Ready.
func installAppAndWait(appName string) {
	ctx := harness.Default.Context()
	version := harness.Default.AppVersion()
	GinkgoWriter.Printf("Installing %s @ %s\n", appName, version)
	Expect(harness.Default.InstallApp(ctx, appName, version)).To(Succeed())

	if baked, ok := bakedManifestApps[appName]; ok {
		for _, d := range baked.deployments {
			GinkgoWriter.Printf("Waiting for deployment %s/%s to become Available\n", baked.namespace, d)
			Expect(harness.WaitForCondition(
				ctx, harness.Default.Client(), deploymentGVK,
				baked.namespace, d, "Available", 10*time.Minute, 5*time.Second,
			)).To(Succeed())
		}
		return
	}

	Expect(waitReady(gitRepositoryGVK, appName+"-manifests", 5*time.Minute)).To(Succeed())
	Expect(waitReady(kustomizationGVK, appName+"-kustomize", 10*time.Minute)).To(Succeed())
}

// waitReady waits for a namespaced object's Ready condition in the app namespace.
func waitReady(gvk schema.GroupVersionKind, name string, timeout time.Duration) error {
	return harness.WaitForCondition(
		harness.Default.Context(), harness.Default.Client(),
		gvk, appNamespace, name, "Ready", timeout, 2*time.Second,
	)
}
