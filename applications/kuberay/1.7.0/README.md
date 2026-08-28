# kuberay

Kubernetes-native operator for managing `RayCluster`, `RayJob`, and `RayService`
resources on NKP.

## Chart Source

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nutanix-cloud-native/charts/kuberay-operator` |
| Chart tag | `1.7.0` |
| Target namespace | `kuberay` |

The chart reference and pinned tag are defined in
`helmrelease/helmrelease.yaml`.

## Default Configuration

This catalog entry does not ship a defaults ConfigMap for Helm values.
The deployment uses upstream chart defaults, and user-provided values are
injected by the app deployment controller at deploy time.

## Dependencies

No hard catalog dependencies are declared in `requiredDependencies` for the
KubeRay Operator itself.

## Validation Notes

- The operator installs cluster-scoped CRDs and controllers for Ray resources.
- `allowMultipleInstances` is `false` in `metadata.yaml`, which is expected for
  CRD-installing apps.

## Links

- [Ray on Kubernetes docs](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)
- [KubeRay project](https://github.com/ray-project/kuberay)
