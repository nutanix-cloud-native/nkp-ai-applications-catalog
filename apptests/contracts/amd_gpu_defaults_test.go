package contracts

import (
	"os"
	"path/filepath"
	"testing"

	"gopkg.in/yaml.v3"
)

type catalogConfigMap struct {
	Data map[string]string `yaml:"data"`
}

func loadGPUValues(t *testing.T, version string) map[string]any {
	t.Helper()

	path := filepath.Join(
		"..", "..", "applications", "amd-gpu-operator", version, "helmrelease", "cm.yaml",
	)
	data, err := os.ReadFile(path)
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

func TestAMDGPUDefaultsPreserveDeviceConfigDuringOperatorUpgrade(t *testing.T) {
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
			driverVersion:   "31.30",
			controllerImage: "v1.5.1-beta.0",
			utilsImage:      "docker.io/rocm/gpu-operator-utils:v1.5.1-beta.0",
			metricsImage:    "rocm/device-metrics-exporter:v1.5.1-beta.0",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.version, func(t *testing.T) {
			t.Parallel()
			values := loadGPUValues(t, tc.version)

			assertions := []struct {
				path     []string
				expected any
			}{
				{[]string{"crds", "defaultCR", "install"}, true},
				{[]string{"crds", "defaultCR", "upgrade"}, false},
				{[]string{"kmm", "enabled"}, false},
				{[]string{"kmm", "watch"}, true},
				{[]string{"node-feature-discovery", "enabled"}, false},
				{[]string{"remediation", "enabled"}, false},
				{[]string{"controllerManager", "manager", "image", "tag"}, tc.controllerImage},
				{[]string{"deviceConfig", "spec", "driver", "enable"}, true},
				{[]string{"deviceConfig", "spec", "driver", "blacklist"}, true},
				{[]string{"deviceConfig", "spec", "driver", "version"}, tc.driverVersion},
				{[]string{"deviceConfig", "spec", "driver", "upgradePolicy", "enable"}, true},
				{[]string{"deviceConfig", "spec", "driver", "upgradePolicy", "rebootRequired"}, false},
				{[]string{"deviceConfig", "spec", "commonConfig", "utilsContainer", "image"}, tc.utilsImage},
				{[]string{"deviceConfig", "spec", "devicePlugin", "enableDevicePlugin"}, false},
				{[]string{"deviceConfig", "spec", "devicePlugin", "enableNodeLabeller"}, false},
				{[]string{"deviceConfig", "spec", "metricsExporter", "enable"}, true},
				{[]string{"deviceConfig", "spec", "metricsExporter", "image"}, tc.metricsImage},
				{[]string{"deviceConfig", "spec", "draDriver", "enable"}, true},
				{[]string{"deviceConfig", "spec", "draDriver", "image"}, "docker.io/rocm/k8s-gpu-dra-driver:v1.0.0"},
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
