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
| TLS secret | `runai-backend-tls` in `runai-backend`, issued by cert-manager (`helmrelease/runai-control-plane-certificate.yaml`, ClusterIssuer `kommander-ca` by default) |
| CA trust | `global.customCA` is enabled by default and reads the CA (`ca.crt`) from `runai-backend-tls`, so no CA bundle secret is needed |
| Sizing | CPU requests (and a few memory requests) are lowered in `helmrelease/cm.yaml` so the control plane fits next to the NKP platform apps on 4 x 8 vCPU workers |
| Pull secret | `runai-reg-creds` in `runai-backend` (private mirror only) |
| Domain input | `runaiDomain` key of the optional `runai-control-plane-config` ConfigMap in the workspace namespace |
| Launch button | `helmrelease/runai-control-plane-ui-dashboard-cm.yaml` links to `https://<runaiDomain>/` |

The control plane only works at the root of its own domain (absolute ingress
paths, Keycloak at `/auth`, URLs built from `global.domain`). Open it at
`https://<runaiDomain>/`; there is no NKP path proxy or redirect.

Run:ai images are pulled anonymously from `nvcr.io/nvidia/runai-oss`.
Third-party images come from `docker.io/bitnamilegacy` (PostgreSQL, NATS,
Thanos), `docker.io/traefik`, `quay.io/keycloak`, and
`registry.access.redhat.com/ubi9`.

## Install Flow

The app needs no overrides: the namespace, TLS certificate, CA trust, ingress
class, and resource sizing are all defaults.

1. Point a DNS record for the control-plane FQDN at the `kommander-traefik`
   load balancer. For a lab name that is not in DNS (for example
   `runai.local`), also add the name to CoreDNS on every cluster that talks to
   the control plane, because the control plane and the Run:ai clusters call
   the domain over HTTPS from inside the cluster:

   ```
   hosts {
      <kommander-traefik LB IP> runai.local
      fallthrough
   }
   ```

2. Create the `runai-control-plane-config` ConfigMap in the workspace
   namespace with the FQDN:

   ```bash
   kubectl create configmap runai-control-plane-config -n <workspace-namespace> \
     --from-literal=runaiDomain=runai.mycorp.local
   ```

   To issue the certificate from a different cert-manager issuer (for example
   a public CA), also set `runaiTlsIssuerName` and `runaiTlsIssuerKind`
   (defaults: `kommander-ca` and `ClusterIssuer`) in the same ConfigMap.

3. Enable the app. Optional overrides:

   ```yaml
   tenantsManager:
     config:
       adminUsername: admin@mycorp.local   # default: test@run.ai
   ```

4. Read the generated admin password:

   ```bash
   kubectl get secret runai-backend-gen-tenants-manager -n runai-backend \
     -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d
   ```

5. Open **NVIDIA Run:ai** at `https://<domain>` (or from the cluster
   **Application Dashboards** tab), log in, and
   create a cluster. Then deploy the
   `runai-cluster` app with the values from the cluster wizard. If the
   certificate is signed by a private CA (the default), the cluster needs that
   CA; see the `runai-cluster` README.

To trust the CA from other clusters, export it:

```bash
kubectl get secret runai-backend-tls -n runai-backend \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > runai-ca.pem
```

## Open Items

- Confirm NVIDIA's redistribution terms allow hosting the chart in our public
  GHCR namespace.
- Validate on an NKP cluster: Traefik ingress, storage, and UI login.
- Air-gapped support is not claimed yet; build a full bundle and verify every
  image is captured before adding the `airgapped` certification.

## Links

- [Install the control plane](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/install-control-plane)
- [System requirements](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/system-requirements)
