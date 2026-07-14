// Package harness defines the interface catalog e2e tests depend on, so test
// files are decoupled from any specific test-harness implementation.
//
// Test files import only this package.
package harness

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

// ClusterLifecycle provisions and releases the cluster under test.
type ClusterLifecycle interface {
	SetupCluster(ctx context.Context) error
	TeardownCluster(ctx context.Context) error
}

// AppLifecycle installs and upgrades the catalog app under test.
type AppLifecycle interface {
	// InstallApp installs the named catalog app at the given version.
	InstallApp(ctx context.Context, name, version string) error
	HasPreviousVersion(name string) bool
	InstallPreviousVersion(ctx context.Context, name string) error
	UpgradeApp(ctx context.Context, name string) error
}

// Backend abstracts the app-test environment: cluster lifecycle, app
// install/upgrade, and the environment accessors tests read. Implementations
// provide the wiring; tests stay backend-agnostic.
type Backend interface {
	ClusterLifecycle
	AppLifecycle

	// Client returns a controller-runtime client for the active cluster.
	Client() ctrlClient.Client
	// Context returns the ambient test context.
	Context() context.Context
	// Namespace is the namespace catalog apps reconcile into.
	Namespace() string
	// AppVersion returns the app version under test (from the -app-version flag).
	AppVersion() string
	// PollInterval is the recommended polling interval for readiness checks.
	PollInterval() time.Duration
	// ApplyYAML server-side applies a multi-doc YAML manifest.
	ApplyYAML(ctx context.Context, data []byte) error
}

// Default is the active backend.
var Default Backend

// Resolves the applications directory by walking up from the working directory.
func ApplicationsDir() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		candidate := filepath.Join(dir, "applications")
		if info, statErr := os.Stat(candidate); statErr == nil && info.IsDir() {
			return candidate, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no applications directory found walking up from working directory")
		}
		dir = parent
	}
}

func WaitForCondition(
	ctx context.Context,
	c ctrlClient.Client,
	gvk schema.GroupVersionKind,
	namespace, name, conditionType string,
	timeout, poll time.Duration,
) error {
	return WaitForConditionReason(ctx, c, gvk, namespace, name, conditionType, "", timeout, poll)
}

// WaitForConditionReason polls the named object until the given status
// condition equals True.
func WaitForConditionReason(
	ctx context.Context,
	c ctrlClient.Client,
	gvk schema.GroupVersionKind,
	namespace, name, conditionType, reason string,
	timeout, poll time.Duration,
) error {
	deadline := time.Now().Add(timeout)
	var lastErr error
	for {
		lastErr = checkCondition(ctx, c, gvk, namespace, name, conditionType, reason)
		if lastErr == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return lastErr
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(poll):
		}
	}
}

func checkCondition(
	ctx context.Context,
	c ctrlClient.Client,
	gvk schema.GroupVersionKind,
	namespace, name, conditionType, reason string,
) error {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(gvk)
	if err := c.Get(ctx, ctrlClient.ObjectKey{Namespace: namespace, Name: name}, obj); err != nil {
		return err
	}

	conditions, found, err := unstructured.NestedSlice(obj.Object, "status", "conditions")
	if err != nil {
		return err
	}
	if !found {
		return fmt.Errorf("%s %s/%s has no status.conditions yet", gvk.Kind, namespace, name)
	}
	for _, c := range conditions {
		cond, ok := c.(map[string]any)
		if !ok {
			continue
		}
		if cond["type"] != conditionType || cond["status"] != "True" {
			continue
		}
		if reason != "" && cond["reason"] != reason {
			continue
		}
		return nil
	}
	return fmt.Errorf("%s %s/%s condition %s not satisfied yet", gvk.Kind, namespace, name, conditionType)
}
