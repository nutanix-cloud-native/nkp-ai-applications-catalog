# training-operator

Kubeflow Training Operator for distributed ML jobs on NKP (PyTorch, TensorFlow,
XGBoost, JAX, MPI, Paddle).

## Chart source

Baked from `kubeflow/manifests` (tag `v1.11.0`, overlay
`applications/training-operator/upstream/overlays/kubeflow`) via
`just bake training-operator`.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nutanix-cloud-native/charts/training-operator` |
| Version | `1.9.2` |
| Namespace | `training-operator` |

CRDs are applied by Flux from `helmrelease/0N-crd.yaml` (`includeCRDs: false`)
before the HelmRelease, so Helm does not own CRD lifecycle.

## Smoke test

Validate an already-enabled Training Operator without reinstalling it.

```sh
export KUBECONFIG=/path/to/workload-cluster.conf

# Preflight
kubectl -n training-operator get deploy,pod,svc
kubectl get crd | grep -E 'pytorchjobs|tfjobs|mpijobs|xgboostjobs|paddlejobs|jaxjobs'

# Minimal CPU-only PyTorchJob (1 epoch MNIST)
kubectl apply -f - <<'EOF'
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: pytorch-smoke
  namespace: default
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      restartPolicy: OnFailure
      template:
        metadata:
          labels:
            sidecar.istio.io/inject: "false"
        spec:
          containers:
          - name: pytorch
            image: docker.io/kubeflowkatib/pytorch-mnist:v1beta1-45c5727
            command:
            - python3
            - /opt/pytorch-mnist/mnist.py
            - --epochs=1
            - --no-cuda
            resources:
              requests:
                cpu: 300m
                memory: 512Mi
              limits:
                cpu: "1"
                memory: 1Gi
EOF

kubectl get pytorchjobs.kubeflow.org -n default
kubectl wait --for=condition=Succeeded pytorchjob/pytorch-smoke -n default --timeout=15m
kubectl delete pytorchjob pytorch-smoke -n default
```

Expected:
- `training-operator` Deployment is Ready.
- Training CRDs are present.
- `pytorch-smoke` reaches Succeeded, then deletes cleanly.

## configOverrides

Workload knobs (from the baked chart):

```yaml
workloads:
  trainingoperator:
    replicas: 1
    resources: {}
    nodeSelector: {}
    tolerations: []
    affinity: {}
```
