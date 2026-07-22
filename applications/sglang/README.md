# SGLang

SGLang is a high-throughput inference server for LLM and multimodal workloads with OpenAI-compatible APIs.

## Chart Source

This catalog entry expects an OCI Helm chart:

| Field | Value |
|---|---|
| Chart OCI URL | `oci://ghcr.io/deepanshu8196/charts/sglang` |
| Chart version | `0.5.15-2` |

If the chart is not present in that OCI path yet, mirror/push it before validating and deploying this app.

## Default Runtime Configuration

Catalog defaults are intentionally generic:

- Image: `lmsysorg/sglang:v0.5.15`
- Service: `ClusterIP` on port `30000`
- Ingress path: `/sglang` via Traefik
- No default model/runtime profile in catalog defaults (set via UI overrides)

## Required UI Overrides

Set these in NKP App Config Overrides before enabling:

- `model.id` (required) — example: `Qwen/Qwen2.5-0.5B-Instruct`

## CPU Profile Override Example

Use this Config Override block for CPU-only clusters:

```yaml
model:
  id: Qwen/Qwen2.5-0.5B-Instruct

image:
  tag: v0.5.15-xeon

extraArgs:
  - "--device"
  - "cpu"
  - "--disable-overlap-schedule"
  - "--disable-cuda-graph"
  - "--trust-remote-code"

env:
  - name: SGLANG_USE_CPU_ENGINE
    value: "1"
  - name: FLASHINFER_DISABLE_VERSION_CHECK
    value: "1"

resources:
  requests:
    cpu: "1"
    memory: 16Gi
  limits:
    cpu: "4"
    memory: 24Gi

startupProbe:
  httpGet:
    path: /health
    port: http
  failureThreshold: 60
  periodSeconds: 10
  timeoutSeconds: 5

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 60
  timeoutSeconds: 5
  failureThreshold: 6
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 120
  timeoutSeconds: 5
  failureThreshold: 6
  periodSeconds: 20
```

## Probe Configuration Note

In chart version `0.5.15-2`, startup/readiness/liveness probes are configurable through Helm values.

## How Model Loading Works

SGLang loads the model directly in the serving process at startup via model flags/config.
You generally do not need a separate model-serving backend in front of SGLang.

For gated/private model downloads, provide a Hugging Face token in your app overrides, for example by
adding an environment variable from a Kubernetes secret in Helm values.

## API Access (No UI)

This app does not provide a UI dashboard. Access it with port-forward or in-cluster DNS:

```bash
kubectl -n sglang port-forward svc/sglang 30000:30000
```

OpenAI-compatible health smoke test:

```bash
curl http://127.0.0.1:30000/v1/models
```

Chat completion example:

```bash
curl -s http://127.0.0.1:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role":"user","content":"Say hello from SGLang"}],
    "temperature": 0.1
  }'
```

## Links

- [SGLang docs](https://docs.sglang.ai/)
- [SGLang GitHub](https://github.com/sgl-project/sglang)
