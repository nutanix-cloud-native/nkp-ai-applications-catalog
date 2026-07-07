package suites

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	fluxhelmv2 "github.com/fluxcd/helm-controller/api/v2"
	apimeta "github.com/fluxcd/pkg/apis/meta"
	"github.com/mesosphere/kommander-applications/apptests/catalog"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"gopkg.in/yaml.v3"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

type appMetadata struct {
	RequiredDependencies []string `yaml:"requiredDependencies"`
}

func registerDefaultTestsWithDependencies(appName string) {
	_ = Describe(appName+" Tests", Label(appName), func() {
		Describe("Installing "+appName, Ordered, Label("install"), func() {
			var (
				app *catalog.App
				hr  *fluxhelmv2.HelmRelease
			)

			BeforeAll(func() {
				err := catalog.SetupKindCluster()
				Expect(err).ToNot(HaveOccurred())

				err = catalog.Env.InstallLatestFlux(catalog.Ctx)
				Expect(err).ToNot(HaveOccurred())

				err = catalog.WaitForFluxCRDs()
				Expect(err).ToNot(HaveOccurred())

				err = installRequiredDependencies(appName)
				Expect(err).ToNot(HaveOccurred())
			})

			AfterAll(func() {
				Expect(catalog.TeardownCluster()).To(Succeed())
			})

			It("should install successfully with default config", func() {
				app = catalog.NewAppScenario(appName, *catalog.AppVersion).(*catalog.App)
				GinkgoWriter.Printf("Installing %s @ %s\n", app.Name(), *catalog.AppVersion)
				err := app.Install(catalog.Ctx, catalog.Env)
				Expect(err).ToNot(HaveOccurred())
				GinkgoWriter.Printf("Install applied, waiting for HelmRelease to become Ready\n")

				hr = &fluxhelmv2.HelmRelease{
					TypeMeta: metav1.TypeMeta{
						Kind:       fluxhelmv2.HelmReleaseKind,
						APIVersion: fluxhelmv2.GroupVersion.Version,
					},
					ObjectMeta: metav1.ObjectMeta{
						Name:      app.Name(),
						Namespace: catalog.DefaultNamespace,
					},
				}

				Eventually(func() error {
					err := catalog.K8sClient.Get(catalog.Ctx, ctrlClient.ObjectKeyFromObject(hr), hr)
					if err != nil {
						GinkgoWriter.Printf("HelmRelease Get error: %v\n", err)
						return err
					}
					GinkgoWriter.Printf(
						"HelmRelease %s/%s conditions: %v\n",
						hr.Namespace,
						hr.Name,
						hr.Status.Conditions,
					)

					for _, cond := range hr.Status.Conditions {
						if cond.Status == metav1.ConditionTrue && cond.Type == apimeta.ReadyCondition {
							GinkgoWriter.Printf("HelmRelease is Ready!\n")
							return nil
						}
					}
					return fmt.Errorf("helm release not ready yet")
				}).WithPolling(catalog.PollInterval).WithTimeout(10 * time.Minute).Should(Succeed())
			})
		})

		Describe("Upgrading "+appName, Ordered, Label("upgrade"), func() {
			var (
				app *catalog.App
				hr  *fluxhelmv2.HelmRelease
			)

			BeforeAll(func() {
				app = catalog.NewAppScenario(appName, *catalog.AppVersion).(*catalog.App)
				if !app.HasPreviousVersion() {
					Skip("skipping upgrade test: no previous version available")
				}

				err := catalog.SetupKindCluster()
				Expect(err).ToNot(HaveOccurred())

				err = catalog.Env.InstallLatestFlux(catalog.Ctx)
				Expect(err).ToNot(HaveOccurred())

				err = catalog.WaitForFluxCRDs()
				Expect(err).ToNot(HaveOccurred())

				err = installRequiredDependencies(appName)
				Expect(err).ToNot(HaveOccurred())
			})

			AfterAll(func() {
				Expect(catalog.TeardownCluster()).To(Succeed())
			})

			It("should install the previous version successfully", func() {
				err := app.InstallPreviousVersion(catalog.Ctx, catalog.Env)
				Expect(err).ToNot(HaveOccurred())

				hr = &fluxhelmv2.HelmRelease{
					ObjectMeta: metav1.ObjectMeta{
						Name:      app.Name(),
						Namespace: catalog.DefaultNamespace,
					},
				}

				Eventually(func() error {
					err := catalog.K8sClient.Get(catalog.Ctx, ctrlClient.ObjectKeyFromObject(hr), hr)
					if err != nil {
						return err
					}
					for _, cond := range hr.Status.Conditions {
						if cond.Status == metav1.ConditionTrue && cond.Type == apimeta.ReadyCondition {
							return nil
						}
					}
					return fmt.Errorf("helm release not ready yet")
				}).WithPolling(catalog.PollInterval).WithTimeout(10 * time.Minute).Should(Succeed())
			})

			It("should upgrade "+appName+" successfully", func() {
				err := app.Upgrade(catalog.Ctx, catalog.Env)
				Expect(err).ToNot(HaveOccurred())

				hr = &fluxhelmv2.HelmRelease{
					ObjectMeta: metav1.ObjectMeta{
						Name:      app.Name(),
						Namespace: catalog.DefaultNamespace,
					},
				}

				Eventually(func() error {
					err := catalog.K8sClient.Get(catalog.Ctx, ctrlClient.ObjectKeyFromObject(hr), hr)
					if err != nil {
						return err
					}
					for _, cond := range hr.Status.Conditions {
						if cond.Status == metav1.ConditionTrue &&
							cond.Type == apimeta.ReadyCondition &&
							cond.Reason == fluxhelmv2.UpgradeSucceededReason {
							return nil
						}
					}
					return fmt.Errorf("helm release not ready yet")
				}).WithPolling(catalog.PollInterval).WithTimeout(10 * time.Minute).Should(Succeed())
			})
		})
	})
}

func installRequiredDependencies(appName string) error {
	metadataPath, err := metadataPathFor(appName, *catalog.AppVersion)
	if err != nil {
		return err
	}

	// #nosec G304 -- metadataPath is constructed from known repository paths and app/version inputs.
	content, err := os.ReadFile(metadataPath)
	if err != nil {
		return err
	}

	var metadata appMetadata
	if err := yaml.Unmarshal(content, &metadata); err != nil {
		return err
	}

	for _, dep := range metadata.RequiredDependencies {
		switch dep {
		case "cert-manager":
			if err := installCertManagerDependency(); err != nil {
				return err
			}
		case "":
			continue
		default:
			return fmt.Errorf("unsupported requiredDependency %q for app %s", dep, appName)
		}
	}

	return nil
}

func metadataPathFor(appName, version string) (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}

	base := ""
	if _, err := os.Stat(filepath.Join(wd, "applications")); os.IsNotExist(err) {
		base = "../.."
	}

	if version == "" {
		return "", fmt.Errorf("app version is required for metadata lookup")
	}

	return filepath.Abs(filepath.Join(wd, base, "applications", appName, version, "metadata.yaml"))
}

func installCertManagerDependency() error {
	kubeconfig := os.Getenv("E2E_KUBECONFIG")
	if kubeconfig == "" && catalog.Env != nil && catalog.Env.Cluster != nil {
		kubeconfig = catalog.Env.Cluster.KubeconfigFilePath()
	}
	if kubeconfig == "" {
		return fmt.Errorf("no kubeconfig available")
	}

	if err := runHelm(kubeconfig, "repo", "add", "jetstack", "https://charts.jetstack.io"); err != nil &&
		!strings.Contains(err.Error(), "already exists") {
		return err
	}

	if err := runHelm(kubeconfig, "repo", "update"); err != nil {
		return err
	}

	return runHelm(
		kubeconfig,
		"upgrade", "--install", "cert-manager", "jetstack/cert-manager",
		"--namespace", "cert-manager",
		"--create-namespace",
		"--set", "crds.enabled=false",
		"--wait",
		"--timeout", "8m",
	)
}

func runHelm(kubeconfig string, args ...string) error {
	// #nosec G204 -- args are assembled from fixed, internal dependency installer commands.
	cmd := exec.CommandContext(catalog.Ctx, "helm", args...)
	cmd.Env = append(os.Environ(), "KUBECONFIG="+kubeconfig)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("helm %s failed: %w\n%s", strings.Join(args, " "), err, string(out))
	}
	return nil
}
