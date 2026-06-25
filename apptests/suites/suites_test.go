package suites

import (
	"testing"

	"github.com/mesosphere/kommander-applications/apptests/catalog"
)

// enabledApps lists applications that have opt-in E2E tests.
// Add an app name here to get the default install + upgrade template test.
// Apps with a custom <app>_test.go in this package do NOT need to be listed
// here — they register their own Ginkgo blocks directly.
var enabledApps = []string{
	"kagent",
	"milvus-operator",
	"kueue",
	"kai-scheduler",
	"slurm-operator",
}

//nolint:gochecknoinits // init required for test registration before suite runs
func init() {
	catalog.InitSuite()
	for _, app := range enabledApps {
		registerDefaultTestsWithDependencies(app)
	}
}

func TestApplications(t *testing.T) { catalog.RunSuite(t) }
