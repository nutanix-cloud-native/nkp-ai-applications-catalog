#!/usr/bin/env bash
# Fail if catalog KFP tutorial samples regain PyPI/python:3.9 (NCN-118204).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SAMPLES_DIR="${ROOT}/overlays/kubeflow-pipelines/airgap-tutorials/samples"
CM_TEMPLATE="${ROOT}/overlays/kubeflow-pipelines/airgap-tutorials/kfp-airgap-tutorial-samples.yaml"
EXPECTED_IMAGE="ghcr.io/nutanix-cloud-native/kfp-tutorial-runtime:2.15.0"

fail() {
  echo "kfp-airgap-tutorials: $*" >&2
  exit 1
}

shopt -s nullglob
samples=("${SAMPLES_DIR}"/*.yaml)
[[ ${#samples[@]} -gt 0 ]] || fail "no sample YAMLs under ${SAMPLES_DIR}"

for f in "${samples[@]}"; do
  if grep -q 'pip install' "$f"; then
    fail "forbidden 'pip install' in ${f#"$ROOT"/}"
  fi
  if grep -q 'image: python:' "$f"; then
    fail "forbidden 'image: python:' in ${f#"$ROOT"/}"
  fi
  if ! grep -qF "${EXPECTED_IMAGE}" "$f"; then
    fail "missing ${EXPECTED_IMAGE} in ${f#"$ROOT"/}"
  fi
done

[[ -f "${CM_TEMPLATE}" ]] || fail "missing ConfigMap template ${CM_TEMPLATE#"$ROOT"/}"

if ! grep -qE '^binaryData:' "${CM_TEMPLATE}"; then
  fail "ConfigMap template must use binaryData: (Helm must not parse KFP {{ placeholders }})"
fi

for key in data-passing.py.yaml dsl-control.py.yaml sample_config.json; do
  if ! grep -qE "^[[:space:]]*${key}:" "${CM_TEMPLATE}"; then
    fail "ConfigMap template missing binaryData key '${key}'"
  fi
done

# Decode-check pipeline sample keys still match the airgap contract.
while IFS= read -r line; do
  key="${line%%:*}"
  key="${key#"${key%%[![:space:]]*}"}" # trim leading whitespace
  b64="${line#*: }"
  case "$key" in
  data-passing.py.yaml | dsl-control.py.yaml) ;;
  *) continue ;;
  esac
  decoded="$(printf '%s' "$b64" | base64 --decode 2>/dev/null)" || fail "failed to base64-decode '${key}'"
  if grep -q 'pip install' <<<"$decoded"; then
    fail "decoded '${key}' contains 'pip install'"
  fi
  if grep -q 'image: python:' <<<"$decoded"; then
    fail "decoded '${key}' contains 'image: python:'"
  fi
  if ! grep -qF "${EXPECTED_IMAGE}" <<<"$decoded"; then
    fail "decoded '${key}' missing ${EXPECTED_IMAGE}"
  fi
done < <(grep -E '^[[:space:]]+(data-passing\.py\.yaml|dsl-control\.py\.yaml):' "${CM_TEMPLATE}")

echo "kfp-airgap-tutorials: ok (${#samples[@]} samples, binaryData ConfigMap keys present)"
