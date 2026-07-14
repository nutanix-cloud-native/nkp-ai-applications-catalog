# shellcheck shell=bash
# Turn the baked flat manifest into a parameterized Helm chart.
#
# Why: baking removes every override surface, but NKP only lets customers tune a
# published app through AppDeployment.spec.configOverrides, which needs a
# HelmRelease. So a flat manifest has no tuning path. We generate a chart from the
# same pinned ref, exposing an allowlist of workload fields (resources / replicas /
# scheduling) via configOverrides with no drift from what we bake for air-gap.
# See docs/designs/issue-NCN-114473-baked-app-configurability.md (Option B*).
#
# The chart lands in charts/<app>/; the app's helmrelease/ dir holds the
# OCIRepository + HelmRelease + -defaults ConfigMap (the kueue pattern).
# shellcheck disable=SC2154,SC2034

# Fields we expose per workload. Scalars are seeded with the upstream default;
# blocks fall back to the upstream value via `with` when unset.
CHART_SCALAR_FIELDS=(replicas)
CHART_POD_BLOCK_FIELDS=(nodeSelector tolerations affinity)
CHART_CONTAINER_BLOCK_FIELDS=(resources)

# True when this version asks for a generated chart (has a `chart:` block).
chart_config_present() {
  [[ "$(yq -r "$VERSION_SELECTOR | has(\"chart\")" "$CONFIG")" == "true" ]]
}

# Turn a k8s workload name into a Helm-friendly, dot-addressable values key:
# tr -cd deletes everything that is NOT alphanumeric, then we lowercase it.
# Keeping it alphanumeric-only also means our "__" placeholder delimiter can
# split cleanly later without tripping over a stray "__" in the name.
# Example: "ml-pipeline" -> "mlpipeline"
helm_key() { printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'; }

# Emit Chart.yaml. Version/appVersion come from config (fall back to the catalog
# version and the upstream ref respectively).
write_chart_yaml() {
  local chart_version chart_app_version
  chart_version="$(yq -r "$VERSION_SELECTOR | .chart.version // \"$VERSION\"" "$CONFIG")"
  chart_app_version="$(yq -r "$VERSION_SELECTOR | .chart.appVersion // .ref" "$CONFIG")"
  cat >"$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: $APP
description: Auto-generated from baked upstream manifests (NCN-114473). Regenerate with 'just bake $APP'; do not edit by hand.
type: application
version: $chart_version
appVersion: "$chart_app_version"
EOF
}

# Read a workload's current field value out of the rendered manifest so the
# generated values.yaml defaults equal upstream exactly.
extract_scalar() { # kind name jsonpath fallback
  yq -r "select(.kind==\"$1\" and .metadata.name==\"$2\") | $3 // $4" "$RENDERED_FILE" | head -1
}

# Seed values.yaml: one entry per workload, keyed by its helm_key, carrying the
# extracted upstream defaults (empty block defaults render to nothing).
seed_values_entry() { # helmKey kind name container
  local helm_key="$1" kind="$2" name="$3" container="$4"
  local replicas resources_yaml
  replicas="$(extract_scalar "$kind" "$name" ".spec.replicas" 1)"

  KEY="$helm_key" REP="$replicas" yq -i '
    .workloads[strenv(KEY)] = {
      "replicas": (strenv(REP) | tonumber),
      "resources": {}, "nodeSelector": {}, "tolerations": [], "affinity": {}
    }' "$VALUES_FILE"

  # Pull just the .resources block of the named container out of the rendered
  # manifest so values.yaml defaults match upstream exactly.
  # Example output: {limits: {cpu: "1", memory: 512Mi}}
  resources_yaml="$(yq "select(.kind==\"$kind\" and .metadata.name==\"$name\").spec.template.spec.containers[] | select(.name==\"$container\") | .resources" "$RENDERED_FILE")"
  if [[ -n $resources_yaml && $resources_yaml != "null" ]]; then
    printf '%s\n' "$resources_yaml" >"$WORK_DIR/res-$helm_key.yaml"
    KEY="$helm_key" RES="$WORK_DIR/res-$helm_key.yaml" \
      yq -i '.workloads[strenv(KEY)].resources = load(strenv(RES))' "$VALUES_FILE"
  fi
}

# Swap each tunable field for a temporary placeholder string (e.g.
# "__HELMSCALAR__<key>__replicas__<default>"). A later awk pass finds those
# placeholders and turns them into Helm template lines. We use placeholders
# instead of writing Helm syntax directly so the file stays valid YAML that yq
# can keep editing until the very end.
inject_placeholders() { # helmKey kind name container
  local helm_key="$1" kind="$2" name="$3" container="$4"
  local sel="select(.kind==\"$kind\" and .metadata.name==\"$name\")"
  local rep field
  rep="$(extract_scalar "$kind" "$name" ".spec.replicas" 1)"

  yq -i "($sel.spec.replicas) = \"__HELMSCALAR__${helm_key}__replicas__${rep}\"" "$PLACEHOLDER_FILE"

  for field in "${CHART_CONTAINER_BLOCK_FIELDS[@]}"; do
    yq -i "del(($sel.spec.template.spec.containers[] | select(.name==\"$container\")).$field)" "$PLACEHOLDER_FILE"
    yq -i "($sel.spec.template.spec.containers[] | select(.name==\"$container\")).__HELMBLOCK__${helm_key}__$field = \"\"" "$PLACEHOLDER_FILE"
  done

  for field in "${CHART_POD_BLOCK_FIELDS[@]}"; do
    yq -i "del($sel.spec.template.spec.$field)" "$PLACEHOLDER_FILE"
    yq -i "($sel.spec.template.spec).__HELMBLOCK__${helm_key}__$field = \"\"" "$PLACEHOLDER_FILE"
  done
}

generate_chart() {
  CHART_DIR="$REPO_ROOT/charts/$APP"
  VALUES_FILE="$CHART_DIR/values.yaml"
  PLACEHOLDER_FILE="$WORK_DIR/placeholders.yaml"

  echo "==> Generating parameterized chart into $CHART_DIR"
  rm -rf "$CHART_DIR" && mkdir -p "$CHART_DIR/templates"
  echo 'workloads: {}' >"$VALUES_FILE"
  cp "$RENDERED_FILE" "$PLACEHOLDER_FILE"

  # For each configured workload, emit "name|kind|container" for the read loop.
  # Example: {name: ml-pipeline, container: server}
  #          -> "ml-pipeline|Deployment|server"  (kind/container default as shown)
  local spec name kind container helm_key
  while IFS='|' read -r name kind container; do
    [[ -n $name ]] || continue
    helm_key="$(helm_key "$name")"
    echo "    workload: $kind/$name (values key: $helm_key)"
    seed_values_entry "$helm_key" "$kind" "$name" "$container"
    inject_placeholders "$helm_key" "$kind" "$name" "$container"
  done < <(yq -r "$VERSION_SELECTOR | .chart.workloads[] | .name + \"|\" + (.kind // \"Deployment\") + \"|\" + (.container // .name)" "$CONFIG")

  awk -f "$SCRIPT_DIR/bake/parameterize.awk" "$PLACEHOLDER_FILE" >"$CHART_DIR/templates/$APP.yaml"
  write_chart_yaml

  echo "==> Chart ready: $(grep -c '^kind:' "$CHART_DIR/templates/$APP.yaml") resources, $(yq -r '.workloads | keys | length' "$VALUES_FILE") parameterized workload(s)."
}
