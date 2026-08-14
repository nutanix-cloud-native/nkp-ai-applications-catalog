# ollama

Lightweight LLM runtime with an OpenAI-compatible API.

## Chart Source

The ollama Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: ollama-helm/ollama
helmrepoUrl: https://otwld.github.io/ollama-helm/
ocipush: oci://<your-oci-registry>/ollama-helm/ollama
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull ollama-helm/ollama --version 1.72.0

# 3. Push to your OCI registry
helm push ollama-1.72.0.tgz oci://<your-oci-registry>/ollama-helm/ollama
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Default Configuration

The default Helm values (`helmrelease/cm.yaml`) auto-pull the `llama3.2`
model on startup and enable a 30Gi persistent volume for model storage.

## E2E Smoke Test Validation

Use this flow to validate an already deployed `ollama` instance on the NKP
cluster. The test verifies runtime health, model availability, and API
responses without reinstalling the application.

Set kubeconfig:

```sh
export KUBECONFIG=/path/to/workload-cluster.conf
```

Preflight checks for the deployed Ollama instance:

```sh
kubectl -n ollama get deploy,pod,svc
kubectl -n ollama get deploy ollama -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Validate runtime and model path from the serving pod:
- `ollama --version` verifies container runtime startup.
- `ollama list` verifies at least one model is available for inference.

```sh
POD=$(kubectl -n ollama get pods -l app.kubernetes.io/name=ollama -o jsonpath='{.items[0].metadata.name}')
kubectl -n ollama exec "$POD" -- ollama --version
kubectl -n ollama exec "$POD" -- ollama list
```

Validate API path from CI runner or user terminal:

```sh
kubectl -n ollama port-forward svc/ollama 11434:11434 >/tmp/ollama-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID' EXIT
sleep 3
curl -sS http://127.0.0.1:11434/api/tags
```

Expected result:
- Deployment and pod are `READY`.
- Runtime image resolves to a valid `ollama/ollama:<tag>` value.
- `ollama --version` returns a valid version string.
- `ollama list` includes `llama3.2:latest` (or your configured default model).
- `/api/tags` returns JSON with at least one model entry.

### In-cluster endpoint

The chart creates the service `ollama-ollama` in namespace `ollama`.
Use this endpoint from other in-cluster apps:

`http://ollama-ollama.ollama.svc.cluster.local:11434`

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the Ollama favicon in the official repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/ollama/ollama/main/docs/favicon.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/ollama/ollama/main/docs/favicon.svg | base64 | tr -d '\n'
```

## Links

- [ollama.com](https://ollama.com)
- [GitHub (ollama)](https://github.com/ollama/ollama)
- [GitHub (Helm chart)](https://github.com/otwld/ollama-helm)
