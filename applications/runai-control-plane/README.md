# NVIDIA Run:ai Control Plane

Self-hosted NVIDIA Run:ai control plane (UI, API, Keycloak, PostgreSQL, Thanos,
NATS). Pair it with the [`runai-cluster`](../runai-cluster/README.md) app,
which installs the cluster components and registers them with this control
plane.

## Chart Source

The upstream chart is published by NVIDIA on NGC
(`https://helm.ngc.nvidia.com/nvidia/runai`, requires an NGC API key) and is
mirrored into our OCI registry.

| Field | Value |
|-------|-------|
| Upstream chart | `control-plane` |
| Mirrored OCI URL | `oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/charts/control-plane` |
| Chart version | `3.0.20` |

## Deployment Layout

| Item | Value |
|------|-------|
| Namespace | `runai-backend` (required by Run:ai) |
| Helm release name | `runai-backend` (required by Run:ai) |
| Ingress class | `kommander-traefik` |
| TLS secret | `runai-backend-tls` in `runai-backend` |
| Pull secret | `runai-reg-creds` in `runai-backend` (private mirror only) |
| Domain input | `runaiDomain` key of the optional `runai-control-plane-config` ConfigMap in the workspace namespace |
| Launch button | `helmrelease/runai-control-plane-ui-dashboard-cm.yaml` links to `/nkp/runai/` |
| Launch redirect | `helmrelease/runai-control-plane-redirect.yaml` (Traefik `IngressRoute` + `Middleware`) redirects `/nkp/runai/` to `https://<runaiDomain>/` |

The control plane only works at the root of its own domain (absolute ingress
paths, Keycloak at `/auth`, URLs built from `global.domain`), so the NKP path
is a redirect rather than a reverse proxy.

Run:ai images are pulled anonymously from `nvcr.io/nvidia/runai-oss`.
Third-party images come from `docker.io/bitnamilegacy` (PostgreSQL, NATS,
Thanos), `docker.io/traefik`, `quay.io/keycloak`, and
`registry.access.redhat.com/ubi9`.

## Install Flow

1. Create the `runai-backend` namespace and the `runai-backend-tls` secret
   (see the app overview for commands).
2. Point a DNS record for the control-plane FQDN at the `kommander-traefik`
   load balancer.
3. Create the `runai-control-plane-config` ConfigMap in the workspace
   namespace with the FQDN:

   ```bash
   kubectl create configmap runai-control-plane-config -n <workspace-namespace> \
     --from-literal=runaiDomain=runai.mycorp.local
   ```

4. Enable the app with these overrides:

   ```yaml
   tenantsManager:
     config:
       adminUsername: admin@mycorp.local
   ```

5. Read the generated admin password:

   ```bash
   kubectl get secret runai-backend-gen-tenants-manager -n runai-backend \
     -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d
   ```

6. Open **NVIDIA Run:ai** from the cluster **Application Dashboards** tab (or
   `https://<domain>`, or `https://<nkp-ingress>/nkp/runai/`), log in, and
   create a cluster. Then deploy the
   `runai-cluster` app with the values from the cluster wizard.

## Open Items

- Confirm NVIDIA's redistribution terms allow hosting the chart in our public
  GHCR namespace.
- Validate on an NKP cluster: Traefik ingress, storage, and UI login.
- Air-gapped support is not claimed yet; build a full bundle and verify every
  image is captured before adding the `airgapped` certification.

## Links

- [Install the control plane](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/install-control-plane)
- [System requirements](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/system-requirements)
