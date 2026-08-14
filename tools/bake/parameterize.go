package main

// Turn the baked flat manifest into a parameterized Helm chart.
//
// Why: baking removes every override surface, but NKP only lets customers tune a
// published app through AppDeployment.spec.configOverrides, which needs a
// HelmRelease. We generate a chart from the same pinned ref, exposing an
// allowlist of workload fields (resources / replicas / scheduling) via
// configOverrides with no drift from what we bake for air-gap.
//
// Fields are swapped for placeholder strings while we manipulate the YAML as
// nodes (so it stays valid YAML), then expandPlaceholders turns those
// placeholders into Helm template lines — the one step that can't be expressed
// as valid YAML.

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"

	"gopkg.in/yaml.v3"
)

// Fields exposed per workload. Scalars are seeded with the upstream default;
// blocks fall back to the upstream value via `with` when unset.
var (
	containerBlockFields = []string{"resources"}
	podBlockFields       = []string{"nodeSelector", "tolerations", "affinity"}
)

func (c *versionCtx) generateChart() error {
	chartDir := filepath.Join(c.repoRoot, "charts", c.app)
	fmt.Printf("==> Generating parameterized chart into %s\n", chartDir)
	if err := os.RemoveAll(chartDir); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(chartDir, "templates"), dirMode); err != nil {
		return err
	}

	docs, err := splitDocs(c.rendered)
	if err != nil {
		return err
	}

	// values.yaml defaults are read from the un-mutated docs so they equal
	// upstream exactly.
	values, err := buildValues(docs, c.ver.Chart.Workloads)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(chartDir, "values.yaml"), values, fileMode); err != nil {
		return err
	}

	for _, w := range c.ver.Chart.Workloads {
		fmt.Printf("    workload: %s/%s (values key: %s)\n", w.KindOrDefault(), w.Name, helmKey(w.Name))
		r := findWorkload(docs, w)
		if r == nil {
			fmt.Printf("    WARNING: %s/%s not found; skipping placeholders\n", w.KindOrDefault(), w.Name)
			continue
		}
		injectPlaceholders(r, w)
	}

	joined, err := joinDocs(docs)
	if err != nil {
		return err
	}
	template := expandPlaceholders(joined)
	template, err = c.applyInjections(template)
	if err != nil {
		return err
	}
	if err := os.WriteFile(
		filepath.Join(chartDir, "templates", c.app+".yaml"),
		[]byte(template),
		fileMode,
	); err != nil {
		return err
	}
	if err := c.copyOverlayTemplates(chartDir); err != nil {
		return err
	}
	if err := c.writeChartYaml(chartDir); err != nil {
		return err
	}

	fmt.Printf("==> Chart ready: %d resources, %d parameterized workload(s).\n",
		countKinds(template), len(c.ver.Chart.Workloads))
	return nil
}

// Applies literal find/replace injections for custom integrations. Errors if
// a target is missing to prevent silent failures when upstream manifests change.
func (c *versionCtx) applyInjections(template string) (string, error) {
	if c.ver.Chart.Overlay == nil {
		return template, nil
	}
	for _, inj := range c.ver.Chart.Overlay.Injections {
		if !strings.Contains(template, inj.Find) {
			return "", fmt.Errorf("overlay injection target not found in %s chart: %q", c.app, inj.Find)
		}
		template = strings.ReplaceAll(template, inj.Find, inj.Replace)
	}
	return template, nil
}

// Copies the chart's overlay template files verbatim into templates/ (e.g. a
// hand-authored _helpers.tpl), so a re-bake restores them exactly.
func (c *versionCtx) copyOverlayTemplates(chartDir string) error {
	if c.ver.Chart.Overlay == nil {
		return nil
	}
	for _, src := range c.ver.Chart.Overlay.Templates {
		//nolint:gosec // overlay paths come from the bake config, resolved against the repo root
		data, err := os.ReadFile(filepath.Join(c.repoRoot, src))
		if err != nil {
			return err
		}
		dst := filepath.Join(chartDir, "templates", filepath.Base(src))
		//nolint:gosec // dst is filepath.Base of a configured overlay path, written into our chart's templates dir
		if err := os.WriteFile(dst, data, fileMode); err != nil {
			return err
		}
	}
	return nil
}

// Turns a workload name into a Helm-friendly, dot-addressable values key by
// keeping only alphanumerics and lowercasing. Alphanumeric-only also lets the
// "__" placeholder delimiter split cleanly. Example: "ml-pipeline" -> "mlpipeline".
func helmKey(name string) string {
	var b strings.Builder
	for _, r := range name {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return b.String()
}

func findWorkload(docs []*yaml.Node, w Workload) *yaml.Node {
	for _, doc := range docs {
		if r := root(doc); isWorkload(r, w.KindOrDefault(), w.Name) {
			return r
		}
	}
	return nil
}

// Seeds values.yaml: one entry per workload (in config order) carrying its
// upstream replicas and container resources. Empty blocks render as {}/[] so an
// unset override falls back to the upstream value via `with`.
func buildValues(docs []*yaml.Node, workloads []Workload) ([]byte, error) {
	workloadsNode := &yaml.Node{Kind: yaml.MappingNode}
	for _, w := range workloads {
		// A workload missing from the manifest gets no placeholders (generateChart
		// warns), so skip its values entry too rather than emit a dead default.
		r := findWorkload(docs, w)
		if r == nil {
			continue
		}
		replicas := "1"
		resources := emptyMap()
		if rep := mapValue(mapValue(r, "spec"), "replicas"); rep != nil && rep.Value != "" {
			replicas = rep.Value
		}
		if ct := container(podSpec(r), w.ContainerOrDefault()); ct != nil {
			if res := mapValue(ct, "resources"); res != nil {
				resources = res
			}
		}
		entry := &yaml.Node{Kind: yaml.MappingNode}
		addPair(entry, "replicas", intNode(replicas))
		addPair(entry, "resources", resources)
		addPair(entry, "nodeSelector", emptyMap())
		addPair(entry, "tolerations", emptySeq())
		addPair(entry, "affinity", emptyMap())
		addPair(workloadsNode, helmKey(w.Name), entry)
	}
	rootNode := &yaml.Node{Kind: yaml.MappingNode}
	addPair(rootNode, "workloads", workloadsNode)
	return encodeYAML(&yaml.Node{Kind: yaml.DocumentNode, Content: []*yaml.Node{rootNode}})
}

// Swaps a workload's tunable fields for placeholder strings that
// expandPlaceholders later turns into Helm expressions.
func injectPlaceholders(r *yaml.Node, w Workload) {
	key := helmKey(w.Name)
	spec := mapValue(r, "spec")

	def := "1"
	if rep := mapValue(spec, "replicas"); rep != nil {
		if rep.Value != "" {
			def = rep.Value
		}
		rep.Kind, rep.Tag, rep.Style = yaml.ScalarNode, strTag, 0
		rep.Value = scalarPlaceholder(key, "replicas", def)
	} else if spec != nil {
		mapSetString(spec, "replicas", scalarPlaceholder(key, "replicas", def))
	}

	if ct := container(podSpec(r), w.ContainerOrDefault()); ct != nil {
		for _, f := range containerBlockFields {
			mapDelete(ct, f)
			mapSetString(ct, blockPlaceholderKey(key, f), "")
		}
	}
	if pod := podSpec(r); pod != nil {
		for _, f := range podBlockFields {
			mapDelete(pod, f)
			mapSetString(pod, blockPlaceholderKey(key, f), "")
		}
	}
}

// Generates Chart.yaml. sources points at the catalog repo so GHCR links the
// pushed package to it (and inherits its public visibility); home stays upstream.
func (c *versionCtx) writeChartYaml(chartDir string) error {
	chartVersion := c.ver.Chart.Version
	if chartVersion == "" {
		chartVersion = c.ver.Version
	}
	appVersion := c.ver.Chart.AppVersion
	if appVersion == "" {
		appVersion = c.ver.Ref
	}
	description := "Auto-generated from baked upstream manifests. " +
		fmt.Sprintf("Regenerate with 'just bake %s'; do not edit by hand.", c.app)
	content := fmt.Sprintf(`apiVersion: v2
name: %s
description: %s
home: %s
type: application
version: %s
appVersion: "%s"
sources:
  - %s
`, c.app, description, c.repo, chartVersion, appVersion, catalogRepo)
	return os.WriteFile(filepath.Join(chartDir, "Chart.yaml"), []byte(content), fileMode)
}

func scalarPlaceholder(key, field, def string) string {
	return fmt.Sprintf("__HELMSCALAR__%s__%s__%s", key, field, def)
}

func blockPlaceholderKey(key, field string) string {
	return fmt.Sprintf("__HELMBLOCK__%s__%s", key, field)
}

var (
	// blockLineRe matches a block placeholder line: <indent>__HELMBLOCK__<key>__<field>: "".
	blockLineRe = regexp.MustCompile(`^([ \t]*)__HELMBLOCK__([A-Za-z0-9]+)__([A-Za-z]+):`)
	// scalarLineRe matches a scalar placeholder line:
	//   <indent><field>: __HELMSCALAR__<key>__<field>__<default>
	// Matching the whole shape (rather than just spotting the marker) means a
	// stray "__HELMSCALAR__" in upstream text simply won't match and passes
	// through untouched — no length-checking needed.
	scalarLineRe = regexp.MustCompile(`^([ \t]*)(\S+): __HELMSCALAR__([A-Za-z0-9]+)__([A-Za-z]+)__(.+)$`)
	// literal Go-template braces baked into the manifest (e.g. Argo's
	// {{workflow.uid}}) that Helm must emit verbatim.
	literalBraceRe = regexp.MustCompile(`\{\{`)
)

// Turns placeholder lines into Helm template expressions:
//
//	block  -> {{- with .Values.workloads.<key>.<field> }}
//	          <field>:
//	            {{- toYaml . | nindent <indent+2> }}
//	          {{- end }}
//	scalar -> <field>: {{ .Values.workloads.<key>.<field> | default <default> }}
//
// Every other line passes through with literal "{{" escaped so Helm leaves it
// alone.
func expandPlaceholders(manifest string) string {
	var out strings.Builder
	for _, line := range strings.Split(manifest, "\n") {
		if m := blockLineRe.FindStringSubmatch(line); m != nil {
			indent, key, field := m[1], m[2], m[3]
			fmt.Fprintf(&out, "%s{{- with .Values.workloads.%s.%s }}\n", indent, key, field)
			fmt.Fprintf(&out, "%s%s:\n", indent, field)
			fmt.Fprintf(&out, "%s  {{- toYaml . | nindent %d }}\n", indent, len(indent)+2)
			fmt.Fprintf(&out, "%s{{- end }}\n", indent)
			continue
		}
		if m := scalarLineRe.FindStringSubmatch(line); m != nil {
			// "  replicas: __HELMSCALAR__demo__replicas__2"
			//   -> indent="  ", field="replicas", key="demo", default="2"
			indent, field, key, def := m[1], m[2], m[3], m[5]
			fmt.Fprintf(&out, "%s%s: {{ .Values.workloads.%s.%s | default %s }}\n",
				indent, field, key, m[4], def)
			continue
		}
		out.WriteString(literalBraceRe.ReplaceAllString(line, `{{ "{{" }}`))
		out.WriteString("\n")
	}
	return strings.TrimSuffix(out.String(), "\n")
}
