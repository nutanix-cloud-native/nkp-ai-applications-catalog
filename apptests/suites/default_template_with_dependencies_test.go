package suites

import (
	"time"

	fluxhelmv2 "github.com/fluxcd/helm-controller/api/v2"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/nutanix-cloud-native/nkp-ai-applications-catalog/apptests/harness"
)

const helmReleaseReadyTimeout = 10 * time.Minute

var helmReleaseGVK = fluxhelmv2.GroupVersion.WithKind(fluxhelmv2.HelmReleaseKind)

// registerDefaultTestsWithDependencies registers the generic install + upgrade
// template for a HelmRelease-based app, provisioning any dependencies the app
// declares in metadata first. Test bodies talk only to the harness backend.
func registerDefaultTestsWithDependencies(appName string) {
	_ = Describe(appName+" Tests", Label(appName), func() {
		Describe("Installing "+appName, Ordered, Label("install"), func() {
			BeforeAll(func() {
				Expect(harness.Default.SetupCluster(harness.Default.Context())).To(Succeed())
				Expect(provisionDependencies(harness.Default.Context(), appName)).To(Succeed())
			})

			AfterAll(func() {
				Expect(harness.Default.TeardownCluster(harness.Default.Context())).To(Succeed())
			})

			It("should install successfully with default config", func() {
				ctx := harness.Default.Context()
				version := harness.Default.AppVersion()
				GinkgoWriter.Printf("Installing %s @ %s\n", appName, version)
				Expect(harness.Default.InstallApp(ctx, appName, version)).To(Succeed())
				Expect(waitForHelmReleaseReady(appName, "")).To(Succeed())
			})
		})

		Describe("Upgrading "+appName, Ordered, Label("upgrade"), func() {
			BeforeAll(func() {
				if !harness.Default.HasPreviousVersion(appName) {
					Skip("skipping upgrade test: no previous version available")
				}
				Expect(harness.Default.SetupCluster(harness.Default.Context())).To(Succeed())
				Expect(provisionDependencies(harness.Default.Context(), appName)).To(Succeed())
			})

			AfterAll(func() {
				Expect(harness.Default.TeardownCluster(harness.Default.Context())).To(Succeed())
			})

			It("should install the previous version successfully", func() {
				ctx := harness.Default.Context()
				Expect(harness.Default.InstallPreviousVersion(ctx, appName)).To(Succeed())
				Expect(waitForHelmReleaseReady(appName, "")).To(Succeed())
			})

			It("should upgrade "+appName+" successfully", func() {
				ctx := harness.Default.Context()
				Expect(harness.Default.UpgradeApp(ctx, appName)).To(Succeed())
				Expect(waitForHelmReleaseReady(appName, fluxhelmv2.UpgradeSucceededReason)).To(Succeed())
			})
		})
	})
}

// waitForHelmReleaseReady waits for the app's HelmRelease to report Ready=True.
// A non-empty reason additionally requires the Ready condition's reason to match
// (used to assert the upgrade path specifically).
func waitForHelmReleaseReady(appName, reason string) error {
	return harness.WaitForConditionReason(
		harness.Default.Context(), harness.Default.Client(), helmReleaseGVK,
		harness.Default.Namespace(), appName, "Ready", reason,
		helmReleaseReadyTimeout, harness.Default.PollInterval(),
	)
}
