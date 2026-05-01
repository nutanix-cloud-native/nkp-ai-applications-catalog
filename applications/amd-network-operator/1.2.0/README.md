# AMD Network Operator

NKP catalog component for the [AMD Network Operator](https://github.com/ROCm/network-operator).

## Dependencies

This component requires `amd-kmm-operator` to be installed first. The dependency is enforced via both `metadata.yaml` (`requiredDependencies`) and Flux `HelmRelease.spec.dependsOn`.

## Default Configuration

The following subcharts are **disabled** by default because they are provided by other NKP components:

| Subchart | Disabled | Provided By |
|---|---|---|
| `kmm` | `kmm.enabled: false` | `amd-kmm-operator` |
| `node-feature-discovery` | `node-feature-discovery.enabled: false` | Kommander |

## NFD Toleration Requirement

Kommander's NFD worker DaemonSet must include the following toleration to discover AMD NICs on tainted nodes:

```yaml
tolerations:
  - key: "amd-dcm"
    operator: "Equal"
    value: "up"
    effect: "NoExecute"
```

Without this, NFD workers won't run on nodes with the `amd-dcm` taint, and those nodes won't receive AMD NIC feature labels.

## Private Registry Setup

The Network Operator does **not** template a default `NetworkConfig` CR from Helm values. Users must manually create `NetworkConfig` CRs with private registry settings:

```yaml
apiVersion: networking.amd.com/v1alpha1
kind: NetworkConfig
metadata:
  name: my-network-config
  namespace: <workspace-namespace>
spec:
  driver:
    image: "registry.example.com:5000/drivers/amd-network-kmod"
    imageRegistrySecret:
      name: "kmm-registry-dockerconfig"
    # imageRegistryTLS:
    #   insecure: false
    #   insecureSkipTLSVerify: false
```

The `imageRegistrySecret` flows from `NetworkConfig` → `Module.spec.imageRepoSecret` → module-loader pod `imagePullSecrets`, so KMM handles pull/push authentication automatically without any ServiceAccount patching.
