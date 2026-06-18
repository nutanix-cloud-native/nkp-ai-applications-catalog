# AMD Network Operator

NKP catalog component for the [AMD Network Operator](https://github.com/ROCm/network-operator).

## Architecture

```mermaid
graph TD
    subgraph "NKP Platform Layer"
        NFD["Node Feature Discovery<br/>(Kommander)"]
    end

    subgraph "AMD KMM Operator"
        KMM["KMM Controller"]
        DC_SECRET["kmm-registry-dockerconfig<br/>(auto-created)"]
        DS["Registry DaemonSet<br/>(containerd trust)"]
    end

    subgraph "AMD Network Operator"
        CTRL["Network Operator Controller"]
        NC["NetworkConfig CR<br/>(user-created)<br/>selector: amd-nic=true"]
        DP["NIC Device Plugin DaemonSet"]
        ME["Metrics Exporter DaemonSet"]
    end

    subgraph "KMM-Managed (per node)"
        MOD["Module CR<br/>(auto-generated)"]
        KANIKO["Kaniko Build Pod<br/>(driver compilation)"]
        WORKER["KMM Worker Pod<br/>(modprobe load)"]
    end

    subgraph "Worker Node"
        NIC["AMD Pensando NIC"]
        KMOD["ionic / ionic_rdma /<br/>pds_core / tawk_ipc<br/>kernel modules"]
    end

    NFD -->|"labels node<br/>amd-nic=true"| NC
    NC -->|"watched by"| CTRL
    CTRL -->|"creates"| MOD
    CTRL -->|"deploys"| DP
    CTRL -->|"deploys"| ME
    MOD -->|"triggers build"| KANIKO
    KANIKO -->|"pushes image to<br/>private registry"| DC_SECRET
    MOD -->|"triggers load"| WORKER
    WORKER -->|"modprobe"| KMOD
    DS -->|"configures containerd<br/>on every node"| WORKER
    KMOD --- NIC
```

### Driver Build Flow

```mermaid
sequenceDiagram
    participant NFD as NFD Worker
    participant Node as Worker Node
    participant Ctrl as Network Operator Controller
    participant KMM as KMM Controller
    participant Kaniko as Kaniko Build Pod
    participant Reg as Private Registry
    participant Worker as KMM Worker Pod

    NFD->>Node: Detects AMD NIC, sets label amd-nic=true
    Note over Node: User creates NetworkConfig CR targeting this label
    Ctrl->>Ctrl: NetworkConfig selector matches node
    Ctrl->>KMM: Creates Module CR (driver image + build spec)
    KMM->>Kaniko: Spawns Kaniko pod for kernel version
    Kaniko->>Kaniko: Builds driver from OS base image + kernel headers
    Kaniko->>Reg: Pushes built driver image (tagged by kernel version)
    KMM->>Worker: Deploys worker pod on target node
    Worker->>Reg: Pulls driver image (via kmm-registry-dockerconfig)
    Worker->>Node: Runs modprobe to load NIC kernel modules
    Ctrl->>Node: Deploys NIC device plugin + metrics exporter
```

## Key Difference from GPU Operator

The Network Operator **does not** auto-create a `NetworkConfig` CR from Helm values. Users must manually create one after enabling the operator. This is different from the GPU Operator, which auto-creates a `DeviceConfig` named `default`.

> **Important:** Choose a `NetworkConfig` name other than `default` to avoid conflicts with the GPU Operator's `DeviceConfig`, since both CRD controllers use the name to generate a shared Dockerfile ConfigMap.

## Dependencies

| Dependency | Purpose | Enforcement |
|---|---|---|
| `amd-kmm-operator` | Shared KMM instance + registry plumbing | `metadata.yaml` (`dependencies`) -- strongly recommended, not required |
| Node Feature Discovery | NIC hardware detection and labelling | Provided by Kommander platform layer |

## Default Configuration

The following subcharts are **disabled** by default because they are provided by other NKP components:

| Subchart | Disabled | Provided By |
|---|---|---|
| `kmm` | `kmm.enabled: false` | `amd-kmm-operator` |
| `node-feature-discovery` | `node-feature-discovery.enabled: false` | Kommander |
| `multus` | `multus.enabled: false` | NKP v2.18+ |

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

## Node Feature Labels

The operator (via the GPU Operator's NFD rules) produces two NIC labels. Each requires its own `NetworkConfig` CR:

| NFD Label | Meaning |
|---|---|
| `feature.node.kubernetes.io/amd-nic: "true"` | Physical NIC (PF) — Pensando DSC Ethernet Controller |
| `feature.node.kubernetes.io/amd-vnic: "true"` | Virtual NIC (SR-IOV VF) — Pensando DSC Ethernet Controller VF |

## NetworkConfig CR (Private Registry)

After enabling the operator, create a `NetworkConfig` CR that aligns with the `kmm-registry-credentials` secret created for the AMD KMM Operator:

```yaml
apiVersion: amd.com/v1alpha1
kind: NetworkConfig
metadata:
  name: network              # must NOT be "default" — see note above
  namespace: <workspace-namespace>
spec:
  selector:
    feature.node.kubernetes.io/amd-nic: "true"
  driver:
    enable: true
    image: "<registry-host>:<port>/<project>/amdnetwork_kmod"
    imageBuild:
      baseImageRegistry: "<registry-host>:<port>/<project>"
      baseImageRegistryTLS:
        insecure: false
        insecureSkipTLSVerify: false
    imageRegistrySecret:
      name: "kmm-registry-dockerconfig"
    imageRegistryTLS:
      insecure: false
      insecureSkipTLSVerify: false
```

### Override Fields

| Field | Description |
|---|---|
| `driver.image` | Registry path where built NIC driver images are pushed/pulled. Do not include a tag; the operator manages tags automatically. |
| `driver.imageRegistrySecret.name` | Must be `kmm-registry-dockerconfig`, auto-created by the AMD KMM Operator reconciler. |
| `driver.imageBuild.baseImageRegistry` | Private mirror hosting OS base images (e.g. `ubuntu:24.04`) for Kaniko builds. Avoids Docker Hub rate limits. |
| `driver.imageRegistryTLS.insecure` | Set `true` for plain HTTP registries. |
| `driver.imageRegistryTLS.insecureSkipTLSVerify` | Set `true` for self-signed certificates. |

### Credential Flow

```mermaid
graph LR
    A["kmm-registry-dockerconfig<br/>(auto-created by KMM Operator)"] -->|"referenced in"| B["NetworkConfig<br/>imageRegistrySecret"]
    B -->|"propagated to"| C["Module CR<br/>imageRepoSecret"]
    C -->|"injected into"| D["Kaniko Build Pod<br/>(push auth)"]
    C -->|"injected into"| E["KMM Worker Pod<br/>(pull auth)"]
```

## Install / Uninstall

**Install:** It is strongly recommended to enable `amd-kmm-operator` first, then `amd-network-operator`. Without a KMM instance, driver builds will not function.

**Uninstall:** Disable `amd-network-operator` first, then `amd-kmm-operator`.
