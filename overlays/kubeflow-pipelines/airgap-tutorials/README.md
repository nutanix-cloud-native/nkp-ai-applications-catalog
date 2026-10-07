# Airgap-ready KFP UI tutorials

Upstream Kubeflow Pipelines ships tutorial samples that run
`pip install kfp==…` inside `python:3.9` component pods. That fails in
air-gapped clusters (NCN-118204).

## What we ship

- Rewritten pipeline YAMLs under `samples/` that use
  `ghcr.io/nutanix-cloud-native/kfp-tutorial-runtime:2.15.0` (kfp preinstalled)
  and drop the pip wrapper from each executor command.
- `samples/sample_config.json` with the same `/samples/tutorials/...` file
  paths as upstream, but pipeline **names** suffixed `-airgap` so a restart
  loads new PipelineVersions instead of skipping sticky upstream names.
- Helm ConfigMap template `kfp-airgap-tutorial-samples.yaml`, copied into the
  baked chart via `scripts/bake-apps.yaml` `chart.overlay.templates`, and
  volume-mounted over the api-server sample paths + `/config/sample_config.json`.
  The ConfigMap uses `binaryData:` (base64) so Helm does not parse KFP
  `{{$}}` / `{{$.inputs...}}` placeholders as template actions.

## Regenerate the ConfigMap template

After editing anything under `samples/`:

```bash
python3 - <<'PY'
import base64
from pathlib import Path
samples = Path("overlays/kubeflow-pipelines/airgap-tutorials/samples")
out = Path("overlays/kubeflow-pipelines/airgap-tutorials/kfp-airgap-tutorial-samples.yaml")
keys = [
    ("data-passing.py.yaml", samples / "data-passing.py.yaml"),
    ("dsl-control.py.yaml", samples / "dsl-control.py.yaml"),
    ("sample_config.json", samples / "sample_config.json"),
]
lines = [
    "apiVersion: v1",
    "kind: ConfigMap",
    "metadata:",
    "  name: kfp-airgap-tutorial-samples",
    "  namespace: kubeflow",
    "  labels:",
    "    app: ml-pipeline",
    "    application-crd-id: kubeflow-pipelines",
    "binaryData:",
]
for key, path in keys:
    lines.append(f"  {key}: {base64.b64encode(path.read_bytes()).decode('ascii')}")
out.write_text("\n".join(lines) + "\n")
print("wrote", out)
PY
```

Then re-bake (`just bake kubeflow-pipelines`) so the chart picks up the
template and injections.

## Sticky sample names on upgrade

ml-pipeline skips importing a sample when a PipelineVersion with that `name`
already exists. Renaming to `*-airgap` forces a fresh load. If an older broken
tutorial was already imported, delete it in the UI (or via API) so operators
are not left with the upstream pip-based version.

## Verify gate

```bash
bash scripts/verify/kfp-airgap-tutorials.sh
```

Also run via `just verify-kfp-airgap-tutorials` / `just check`. Fails if
samples regain `pip install` / `image: python:` or lose the tutorial-runtime
image, or if the ConfigMap template drops a binaryData key.
