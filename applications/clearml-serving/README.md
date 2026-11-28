# clearml-serving

ClearML Serving: model inference service driven by the ClearML model registry.
Requires the `clearml` application.

## Access

The inference API serves models at `/serve/<model>` and has no base-path setting,
so it cannot be placed under an NKP Traefik subpath such as `/nkp/clearml-serving`.
The Service is **ClusterIP** with ingress disabled (same approach as `open-webui`
and `clearml`). Access it with port-forward:

```bash
kubectl -n clearml-serving port-forward svc/clearml-serving-clearml-serving-inference 8080:8080
curl -X POST http://127.0.0.1:8080/serve/<model> -d '{...}'
```

In-cluster:
`http://clearml-serving-clearml-serving-inference.clearml-serving.svc.cluster.local:8080/serve/<model>`

Service names carry a `clearml-serving-clearml-serving-` prefix because Flux names
the Helm release `<targetNamespace>-<HelmRelease name>`.

## Configuration

The catalog defaults point the serving pods at the in-cluster ClearML Server services
(`clearml.apiHost`, `filesHost` and `webHost`, `clearml-clearml-*` in the `clearml`
namespace). The credentials and Serving Service ID are placeholders, so you **must**
override them. Override these configs in the NKP UI, disable ClearML Serving, wait
2-3 minutes for the pods to terminate, and re-enable the app.

```yaml
clearml:
  apiAccessKey: "<access key>"
  apiSecretKey: "<secret key>"
  servingTaskId: "<serving service id>"
```
