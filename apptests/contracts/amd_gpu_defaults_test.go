package contracts

import (
	"os"
	"path/filepath"
	"testing"

	"gopkg.in/yaml.v3"
)

const (
	enabledKey      = "enabled"
	imageKey        = "image"
	deviceConfigKey = "deviceConfig"
	specKey         = "spec"
	driverKey       = "driver"
	enableKey       = "enable"
)

type catalogConfigMap struct {
	Data map[string]string `yaml:"data"`
}

func loadGPUValues(t *testing.T, version string) map[string]any {
	t.Helper()

	path := filepath.Join(
		"..", "..", "applications", "amd-gpu-operator", version, "helmrelease", "cm.yaml",
	)
	data, err := os.ReadFile(path) //nolint:gosec // Versions are fixed repository fixtures.
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	var configMap catalogConfigMap
	if err := yaml.Unmarshal(data, &configMap); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}

	var values map[string]any
	if err := yaml.Unmarshal([]byte(configMap.Data["values.yaml"]), &values); err != nil {
		t.Fatalf("decode embedded values in %s: %v", path, err)
	}
	return values
}

func nestedValue(t *testing.T, values map[string]any, path ...string) any {
	t.Helper()

	var current any = values
	for _, field := range path {
		object, ok := current.(map[string]any)
		if !ok {
			t.Fatalf("%v is not an object while reading %v", current, path)
		}
		current, ok = object[field]
		if !ok {
			t.Fatalf("missing %q while reading %v", field, path)
		}
	}
	return current
}

func TestAMDGPUCatalogDefaults(t *testing.T) {
	t.Parallel()

	cases := []struct {
		version         string
		driverVersion   string
		controllerImage string
		utilsImage      string
		metricsImage    string
	}{
		{
			version:         "1.5.0",
			driverVersion:   "30.20.1",
			controllerImage: "v1.5.0",
			utilsImage:      "docker.io/rocm/gpu-operator-utils:v1.5.0",
			metricsImage:    "rocm/device-metrics-exporter:v1.5.0",
		},
		{
			version:         "1.5.1-beta.0",
			driverVersion:   "31.40",
			controllerImage: "v1.5.1-beta.0",
			utilsImage:      "docker.io/rocm/gpu-operator-utils:v1.5.1-beta.0",
			metricsImage:    "rocm/device-metrics-exporter:v1.5.1-beta.0",
		},
	}

	for _, tc := range cases {
		t.Run(tc.version, func(t *testing.T) {
			t.Parallel()
			values := loadGPUValues(t, tc.version)

			assertions := []struct {
				path     []string
				expected any
			}{
				{[]string{"crds", "defaultCR", "install"}, true},
				{[]string{"crds", "defaultCR", "upgrade"}, true},
				{[]string{"kmm", enabledKey}, false},
				{[]string{"kmm", "watch"}, true},
				{[]string{"node-feature-discovery", enabledKey}, false},
				{[]string{"remediation", enabledKey}, false},
				{[]string{"controllerManager", "manager", imageKey, "tag"}, tc.controllerImage},
				{[]string{deviceConfigKey, specKey, driverKey, enableKey}, true},
				{[]string{deviceConfigKey, specKey, driverKey, "blacklist"}, true},
				{[]string{deviceConfigKey, specKey, driverKey, "version"}, tc.driverVersion},
				{[]string{deviceConfigKey, specKey, driverKey, "upgradePolicy", enableKey}, true},
				{[]string{deviceConfigKey, specKey, driverKey, "upgradePolicy", "rebootRequired"}, false},
				{[]string{deviceConfigKey, specKey, "commonConfig", "utilsContainer", imageKey}, tc.utilsImage},
				{[]string{deviceConfigKey, specKey, "devicePlugin", "enableDevicePlugin"}, false},
				{[]string{deviceConfigKey, specKey, "devicePlugin", "enableNodeLabeller"}, false},
				{[]string{deviceConfigKey, specKey, "metricsExporter", enableKey}, true},
				{[]string{deviceConfigKey, specKey, "metricsExporter", imageKey}, tc.metricsImage},
				{[]string{deviceConfigKey, specKey, "draDriver", enableKey}, true},
				{[]string{deviceConfigKey, specKey, "draDriver", imageKey}, "docker.io/rocm/k8s-gpu-dra-driver:v1.0.0"},
			}

			for _, assertion := range assertions {
				actual := nestedValue(t, values, assertion.path...)
				if actual != assertion.expected {
					t.Errorf("%v = %v, want %v", assertion.path, actual, assertion.expected)
				}
			}
		})
	}
}
