# clearml

ClearML Server: experiment tracking, model registry, datasets, and web UI.

## Access

The ClearML web UI cannot be served under an NKP Traefik subpath such as
`/nkp/clearml`. It is a single-page app with no base-path setting; it requests
assets and `/api` at the root of the page origin. It is therefore a **ClusterIP**
Service with ingress disabled (same approach as `open-webui`). Access it with
port-forward:

```bash
kubectl -n clearml port-forward svc/clearml-clearml-webserver 8080:80
```

Then open `http://127.0.0.1:8080/`.

The web server proxies `/api` and `/files` to the API and file servers, so the UI
needs only this one forward. For the ClearML Python SDK from outside the cluster,
forward the API and file servers too:

```bash
kubectl -n clearml port-forward svc/clearml-clearml-apiserver 8008:8008
kubectl -n clearml port-forward svc/clearml-clearml-fileserver 8081:8081
```

Service names carry a `clearml-clearml-` prefix because Flux names the Helm release
`<targetNamespace>-<HelmRelease name>`.

## Authentication

ClearML uses its own login (not Dex / Traefik Forward Auth).
