# Steps to push the catalog bundle and Helm charts to OCI (e.g. GHCR)

Use these steps to build the catalog bundle and push individual Helm charts to an OCI registry. Charts are pushed to `oci://ghcr.io/nutanix-cloud-native/charts`; the Flux manifests in this repo use `oci://ghcr.io/nutanix-cloud-native/charts/<chart-name>`.

You can either run the workflows (with the job values below) or run the manual commands locally.

---

# 1. Log in to GHCR (manual push only)

```bash
echo $GITHUB_TOKEN | helm registry login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

---

# 2. Push catalog bundle to OCI

**Workflow:** [Publish OCI Artifacts](https://github.com/nutanix-cloud-native/nkp-ai-applications-catalog/actions/workflows/publish-oci-artifacts.yaml)

**Job values:**

| Input           | Value                                                          |
|-----------------|----------------------------------------------------------------|
| COLLECTION_TAG  | `v0.1.0`                                                      |
| REGISTRY        | `oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog` (default) |

**Manual push (optional):**

```bash
nkp create catalog-bundle --collection-tag v0.1.0
nkp push bundle \
  --bundle ./nkp-ai-applications-catalog-v0.1.0.tar \
  --to-registry oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog
```

**OCI URL used for catalog collection:** `oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection`  
**Tag:** `v0.1.0`

---

# 3. Push individual Helm charts to OCI (ghcr.io/nutanix-cloud-native/charts)

**Workflow:** [Publish Chart to GHCR](https://github.com/nutanix-cloud-native/nkp-ai-applications-catalog/actions/workflows/publish-chart-oci.yaml)

The workflow defaults to `oci://ghcr.io/nutanix-cloud-native/charts`. Charts are pushed as `oci://ghcr.io/nutanix-cloud-native/charts/<chart-name>`.

## Job values for each chart

| Chart       | chart_repo                                              | repo_name   | chart_name   | chart_version | target_oci_registry (optional, uses default)        |
|-------------|---------------------------------------------------------|-------------|--------------|---------------|-----------------------------------------------------|
| Weaviate   | `https://weaviate.github.io/weaviate-helm/`             | `weaviate`  | `weaviate`   | `17.7.0`      | `oci://ghcr.io/nutanix-cloud-native/charts`         |
| vLLM       | `https://open-source-ai-dev.github.io/vllm-helm-chart`  | `vllm`      | `vllm`       | `0.1.1`       | `oci://ghcr.io/nutanix-cloud-native/charts`         |
| Open WebUI | `https://helm.openwebui.com/`                           | `open-webui`| `open-webui` | `12.0.1`      | `oci://ghcr.io/nutanix-cloud-native/charts`         |
| Ollama     | `https://otwld.github.io/ollama-helm/`                  | `ollama-helm` | `ollama`   | `1.39.0`      | `oci://ghcr.io/nutanix-cloud-native/charts`         |

**Note:** `repo_name` is the Helm repo alias used in `helm repo add` and `helm pull <repo_name>/<chart_name>`. It must match the repo index (e.g. Weaviate uses `weaviate`, Ollama uses `ollama-helm`).

## Manual push (all charts)

```bash
# 1. Log in to GHCR
echo $GITHUB_TOKEN | helm registry login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 2. Weaviate 17.7.0
helm repo add weaviate https://weaviate.github.io/weaviate-helm/
helm repo update
helm pull weaviate/weaviate --version 17.7.0
helm push weaviate-17.7.0.tgz oci://ghcr.io/nutanix-cloud-native/charts

# 3. vLLM 0.1.1
helm repo add vllm https://open-source-ai-dev.github.io/vllm-helm-chart
helm repo update
helm pull vllm/vllm --version 0.1.1
helm push vllm-0.1.1.tgz oci://ghcr.io/nutanix-cloud-native/charts

# 4. Open WebUI 12.0.1
helm repo add open-webui https://helm.openwebui.com/
helm repo update
helm pull open-webui/open-webui --version 12.0.1
helm push open-webui-12.0.1.tgz oci://ghcr.io/nutanix-cloud-native/charts

# 5. Ollama 1.39.0 (repo_name=ollama-helm, chart_name=ollama)
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update
helm pull ollama-helm/ollama --version 1.39.0
helm push ollama-1.39.0.tgz oci://ghcr.io/nutanix-cloud-native/charts
```

**OCI URLs used in Flux:** `oci://ghcr.io/nutanix-cloud-native/charts/weaviate`, `oci://ghcr.io/nutanix-cloud-native/charts/vllm`, etc.

---

# 4. Deploy the catalog on an NKP cluster

After pushing the catalog bundle, create the catalog collection on your cluster:

```bash
nkp create catalog-collection \
  --url oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection \
  --tag v0.1.0 \
  --workspace <workspace-name>
```

---

The Flux OCIRepository resources use `oci://ghcr.io/nutanix-cloud-native/charts/<chart-name>`, matching the **Publish Chart to GHCR** workflow output.
