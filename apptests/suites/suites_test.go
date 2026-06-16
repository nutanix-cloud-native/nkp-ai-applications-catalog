package suites

import (
	"context"
	"testing"

	"github.com/mesosphere/kommander-applications/apptests/catalog"
	. "github.com/onsi/ginkgo/v2"
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// enabledApps lists applications that have opt-in E2E tests.
// Add an app name here to get the default install + upgrade template test.
// Apps with a custom <app>_test.go in this package do NOT need to be listed
// here — they register their own Ginkgo blocks directly.
var enabledApps = []string{
	"kagent",
}

func applyFluxFeatureGates() {
	if catalog.K8sClient == nil {
		return
	}

	GinkgoWriter.Println("INFO: Applying Flux Feature Gates (DisableChartDigestTracking=true)")

	patchData := []byte(`[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--feature-gates=DisableChartDigestTracking=true"
        }
    ]`)
	patch := client.RawPatch(types.JSONPatchType, patchData)

	namespaces := []string{"flux-system", "kommander-flux"}
	for _, ns := range namespaces {
		deploy := &appsv1.Deployment{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "helm-controller",
				Namespace: ns,
			},
		}

		if err := catalog.K8sClient.Patch(context.TODO(), deploy, patch); err == nil {
			GinkgoWriter.Printf("SUCCESS: Patched helm-controller in '%s'\n", ns)
			return
		}
	}

	GinkgoWriter.Println("WARNING: Failed to patch helm-controller. It may not be ready yet.")
}

var _ = JustBeforeEach(func() {
	applyFluxFeatureGates()
})

//nolint:gochecknoinits // init required for test registration before suite runs
func init() {
	catalog.InitSuite()
	for _, app := range enabledApps {
		catalog.RegisterDefaultTests(app)
	}
}

func TestApplications(t *testing.T) { catalog.RunSuite(t) }
