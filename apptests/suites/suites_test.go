package suites

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mesosphere/kommander-applications/apptests/catalog"
)

// registeredLabels lists apps that have a custom _test.go in this package.
// Apps NOT listed here get the default install+upgrade template test via
// catalog.ScanAndRegister.
var registeredLabels = map[string]bool{
	// Add app names here when you create a custom <app>_test.go that
	// needs pre-install setup (secrets, ConfigMap patches, etc.).
	// Example:
	//   "kasm": true,
}

func init() {
	catalog.InitSuite()

	repoRoot, _ := filepath.Abs(filepath.Join("..", ".."))
	if envRoot := os.Getenv("CATALOG_REPO_ROOT"); envRoot != "" {
		repoRoot = envRoot
	}
	catalog.ScanAndRegister(repoRoot, registeredLabels)
}

func TestApplications(t *testing.T) { catalog.RunSuite(t) }
