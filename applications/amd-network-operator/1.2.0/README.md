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

## ServiceAccount Reconciler

A CronJob (`amd-network-operator-sa-reconciler`) runs every 5 minutes and ensures the `kmm-registry-dockerconfig` imagePullSecret is present on the `amd-network-operator-kmm-module-loader` ServiceAccount. This is additive — existing imagePullSecrets are preserved.
