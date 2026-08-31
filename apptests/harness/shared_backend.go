package harness

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/nutanix-cloud-native/nkp-catalog-tests/catalog"
	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

const disableChartDigestTracking = "--feature-gates=DisableChartDigestTracking=true"

// sharedBackend adapts nkp-catalog-tests/catalog to the Backend interface.
type sharedBackend struct{}

//nolint:gochecknoinits // wires the default backend before tests run
func init() {
	Default = &sharedBackend{}
}

func (b *sharedBackend) SetupCluster(ctx context.Context) error {
	// Force destroy existing cluster to avoid node conflicts during setup.
	if !catalog.UseExistingCluster && catalog.Env != nil && catalog.Env.Cluster != nil {
		_ = catalog.Env.Destroy(ctx)
		catalog.Env.SetCluster(nil)
	}

	if err := catalog.SetupKindCluster(); err != nil {
		return err
	}
	if err := catalog.Env.InstallLatestFlux(ctx); err != nil {
		return err
	}
	if err := catalog.WaitForFluxCRDs(); err != nil {
		return err
	}
	return applyKommanderFluxSettings(ctx)
}

// Brings the test cluster's Flux in line with how kommander configures
// it in production, so catalog apps are exercised under real conditions.
// In future, we may consider installing kommander-flux itself.
func applyKommanderFluxSettings(ctx context.Context) error {
	key := types.NamespacedName{Namespace: "kommander-flux", Name: "helm-controller"}
	deploy := &appsv1.Deployment{}
	if err := catalog.K8sClient.Get(ctx, key, deploy); err != nil {
		return fmt.Errorf("getting helm-controller: %w", err)
	}

	container := &deploy.Spec.Template.Spec.Containers[0]
	if slices.Contains(container.Args, disableChartDigestTracking) {
		return nil
	}
	container.Args = append(container.Args, disableChartDigestTracking)
	if err := catalog.K8sClient.Update(ctx, deploy); err != nil {
		return fmt.Errorf("enabling DisableChartDigestTracking on helm-controller: %w", err)
	}
	return waitForRollout(ctx, key)
}

func waitForRollout(ctx context.Context, key types.NamespacedName) error {
	return wait.PollUntilContextTimeout(ctx, 2*time.Second, 2*time.Minute, true,
		func(ctx context.Context) (bool, error) {
			deploy := &appsv1.Deployment{}
			if err := catalog.K8sClient.Get(ctx, key, deploy); err != nil {
				return false, err
			}
			desired := int32(1)
			if deploy.Spec.Replicas != nil {
				desired = *deploy.Spec.Replicas
			}
			return deploy.Status.ObservedGeneration >= deploy.Generation &&
				deploy.Status.UpdatedReplicas == desired &&
				deploy.Status.AvailableReplicas == desired, nil
		})
}

func (b *sharedBackend) TeardownCluster(context.Context) error {
	return catalog.TeardownCluster()
}

func (b *sharedBackend) Client() ctrlClient.Client { return catalog.K8sClient }

func (b *sharedBackend) Context() context.Context {
	if catalog.Ctx != nil {
		return catalog.Ctx
	}
	return context.Background()
}

func (b *sharedBackend) Namespace() string { return catalog.DefaultNamespace }

func (b *sharedBackend) AppVersion() string {
	if catalog.AppVersion == nil {
		return ""
	}
	return *catalog.AppVersion
}

func (b *sharedBackend) PollInterval() time.Duration { return catalog.PollInterval }

func (b *sharedBackend) ApplyYAML(ctx context.Context, data []byte) error {
	return catalog.Env.ApplyYAMLFileRaw(ctx, data, nil)
}

func (b *sharedBackend) InstallApp(ctx context.Context, name, version string) error {
	return catalog.NewAppScenario(name, version).Install(ctx, catalog.Env)
}

func (b *sharedBackend) HasPreviousVersion(name string) bool {
	_, err := previousVersion(name, b.AppVersion())
	return err == nil
}

func (b *sharedBackend) InstallPreviousVersion(ctx context.Context, name string) error {
	prev, err := previousVersion(name, b.AppVersion())
	if err != nil {
		return err
	}
	return catalog.NewAppScenario(name, prev).Install(ctx, catalog.Env)
}

func (b *sharedBackend) UpgradeApp(ctx context.Context, name string) error {
	return b.app(name).Upgrade(ctx, catalog.Env)
}

func (b *sharedBackend) app(name string) *catalog.App {
	return catalog.NewAppScenario(name, b.AppVersion()).(*catalog.App)
}

// Gets the version just before 'current' (or the second-to-latest) for upgrade tests.
func previousVersion(name, current string) (string, error) {
	versions, err := appVersionDirs(name)
	if err != nil {
		return "", err
	}
	if current == "" {
		if len(versions) < 2 {
			return "", fmt.Errorf("app %q has no previous version to upgrade from", name)
		}
		return versions[len(versions)-2], nil
	}
	prev := ""
	for _, v := range versions {
		if v < current {
			prev = v // versions are ascending, so the last match is the closest prior
		}
	}
	if prev == "" {
		return "", fmt.Errorf("app %q has no version before %q to upgrade from", name, current)
	}
	return prev, nil
}

// appVersionDirs returns an app's version directory names, sorted ascending.
// Only real subdirectories count; files and dot-prefixed entries (for example
// .catalog-source.yaml) are catalog metadata, not versions.
func appVersionDirs(name string) ([]string, error) {
	dir, err := appDir(name)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var versions []string
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			versions = append(versions, e.Name())
		}
	}
	slices.Sort(versions)
	return versions, nil
}

// appDir resolves applications/<name> from wherever the tests run.
func appDir(name string) (string, error) {
	appsDir, err := ApplicationsDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(appsDir, name), nil
}

func InitSuite() { catalog.InitSuite() }

func RunSuite(t *testing.T) {
	t.Helper()
	catalog.RunSuite(t)
}
