# shellcheck shell=bash
# Outputs: dry-run summary and the final bake into the app's helmrelease/ dir.
# Sourced by scripts/build-baked-manifests.sh.
# Globals are assigned here but consumed across stages, so silence SC2154
# (referenced-not-assigned) and SC2034 (assigned-not-used) for this fragment.
# shellcheck disable=SC2154,SC2034

print_dry_run_summary() {
  echo "==> Dry-run complete. Manifest rendered at: $RENDERED_FILE"
  echo "    Images:"
  printf '%s\n' "$ALL_IMAGES" | sed 's/^/      /'
}

# Source for app-test harness and production Flux Kustomization rendering.
save_final_manifests() {
  echo "==> Baking manifests into $MANIFESTS_DIR"
  mkdir -p "$MANIFESTS_DIR"
  cp "$RENDERED_FILE" "$MANIFESTS_DIR/$APP.yaml"

  cat <<EOF >"$MANIFESTS_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- $APP.yaml
EOF

  echo "==> Success! Baked $(grep -c '^kind:' "$MANIFESTS_DIR/$APP.yaml") resources."
}
