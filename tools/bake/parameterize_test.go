package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestExpandPlaceholders(t *testing.T) {
	in := strings.Join([]string{
		"spec:",
		"  replicas: __HELMSCALAR__demo__replicas__2",
		"  template:",
		"    spec:",
		"      containers:",
		"      - name: demo",
		`        __HELMBLOCK__demo__resources: ""`,
		`      __HELMBLOCK__demo__nodeSelector: ""`,
		"      env:",
		"      - name: FOO",
		`        value: "{{workflow.uid}}"`,
	}, "\n")

	got := expandPlaceholders(in)

	for _, want := range []string{
		"replicas: {{ .Values.workloads.demo.replicas | default 2 }}",
		"{{- with .Values.workloads.demo.resources }}",
		"  {{- toYaml . | nindent 10 }}", // 8-space indent + 2
		"{{- with .Values.workloads.demo.nodeSelector }}",
		"  {{- toYaml . | nindent 8 }}", // 6-space indent + 2
		`value: "{{ "{{" }}workflow.uid}}"`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("expandPlaceholders output missing %q\n---\n%s", want, got)
		}
	}
}

func TestStripTagAndRegistryPath(t *testing.T) {
	const busybox = "busybox"
	cases := []struct{ in, wantTag string }{
		{"nginx:1.25", "nginx"},
		{"gcr.io/foo/bar:v1", "gcr.io/foo/bar"},
		{"reg:5000/foo:v1", "reg:5000/foo"},
		{busybox, busybox},
	}
	for _, c := range cases {
		if got := stripTag(c.in); got != c.wantTag {
			t.Errorf("stripTag(%q) = %q, want %q", c.in, got, c.wantTag)
		}
	}

	ctx := &versionCtx{registry: "myreg.example.com/proj"}
	paths := map[string]string{
		"gcr.io/foo/bar":    "myreg.example.com/proj/foo/bar",
		"argoproj/argoexec": "myreg.example.com/proj/argoproj/argoexec",
		busybox:             "myreg.example.com/proj/library/busybox",
	}
	for in, want := range paths {
		if got := ctx.registryImagePath(in); got != want {
			t.Errorf("registryImagePath(%q) = %q, want %q", in, got, want)
		}
	}
}

// TestGenerateChartRendersWithHelm parameterizes a synthetic manifest and, when
// helm is on PATH, confirms the generated chart renders and that overrides flow
// through.
func TestGenerateChartRendersWithHelm(t *testing.T) {
	manifest := `apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      nodeSelector:
        disktype: ssd
      containers:
      - name: demo
        image: nginx:1.25
        resources:
          limits:
            cpu: "1"
        env:
        - name: FOO
          value: "{{workflow.uid}}"
`
	repoRoot := t.TempDir()
	c := &versionCtx{
		repoRoot: repoRoot,
		app:      "demo",
		rendered: manifest,
		ver: Version{
			Version: "1.0.0",
			Ref:     "v1.0.0",
			Chart:   &Chart{Workloads: []Workload{{Name: "demo"}}},
		},
	}
	if err := c.generateChart(); err != nil {
		t.Fatalf("generateChart: %v", err)
	}

	chartDir := filepath.Join(repoRoot, "charts", "demo")
	values := readFile(t, filepath.Join(chartDir, "values.yaml"))
	if !strings.Contains(values, "replicas: 2") {
		t.Errorf("values.yaml should seed upstream replicas=2:\n%s", values)
	}
	if !strings.Contains(values, "cpu:") {
		t.Errorf("values.yaml should seed upstream resources:\n%s", values)
	}

	if !have("helm") {
		t.Skip("helm not on PATH; skipping render assertion")
	}
	//nolint:gosec // test invokes helm with a temp chart dir it just generated
	out, err := exec.Command("helm", "template", "demo", chartDir,
		"--set", "workloads.demo.replicas=5").CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, out)
	}
	rendered := string(out)
	if !strings.Contains(rendered, "replicas: 5") {
		t.Errorf("override workloads.demo.replicas=5 did not apply:\n%s", rendered)
	}
	if !strings.Contains(rendered, "{{workflow.uid}}") {
		t.Errorf("literal Argo placeholder should survive rendering:\n%s", rendered)
	}
}

func TestKustomizationFileRewritesImages(t *testing.T) {
	c := &versionCtx{registry: "myreg.example.com", workloadImages: []string{"gcr.io/ml/foo:v1"}}
	c.ver.Namespace = "kubeflow"

	out, err := c.kustomizationFile()
	if err != nil {
		t.Fatalf("kustomizationFile: %v", err)
	}
	var k kustomization
	if err := yaml.Unmarshal([]byte(out), &k); err != nil {
		t.Fatalf("kustomization is not valid YAML: %v\n%s", err, out)
	}
	if k.Namespace != "kubeflow" {
		t.Errorf("namespace = %q, want kubeflow", k.Namespace)
	}
	if len(k.Images) != 1 || k.Images[0].Name != "gcr.io/ml/foo" || k.Images[0].NewName != "myreg.example.com/ml/foo" {
		t.Errorf("image rewrite wrong: %+v", k.Images)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	//nolint:gosec // test reads a file it just generated under t.TempDir()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}
