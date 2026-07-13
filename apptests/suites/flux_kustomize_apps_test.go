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
)

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

// installAppAndWait installs the app and asserts its Flux source + Kustomization
// reach Ready, matching the generic template's success signal.
func installAppAndWait(appName string) {
	ctx := harness.Default.Context()
	version := harness.Default.AppVersion()
	GinkgoWriter.Printf("Installing %s @ %s\n", appName, version)
	Expect(harness.Default.InstallApp(ctx, appName, version)).To(Succeed())

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
