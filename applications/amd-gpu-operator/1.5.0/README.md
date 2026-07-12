# AMD GPU Operator

NKP catalog component for the [AMD GPU Operator](https://github.com/ROCm/gpu-operator) v1.5.0.

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

    subgraph "AMD GPU Operator"
        CTRL["GPU Operator Controller"]
        DC["DeviceConfig 'default'<br/>selector: amd-gpu=true"]
        DRA["DRA Driver DaemonSet<br/>(default GPU resource allocation)"]
        NL["Node Labeller DaemonSet"]
        ME["Metrics Exporter DaemonSet"]
        DP["Device Plugin DaemonSet<br/>(disabled; alternative to DRA)"]
        ANR["Auto Node Remediation<br/>(optional, Argo Workflows)"]
    end

    subgraph "KMM-Managed (per node)"
        MOD["Module CR<br/>(auto-generated)"]
        KANIKO["Kaniko Build Pod<br/>(driver compilation)"]
        WORKER["KMM Worker Pod<br/>(modprobe load)"]
    end

    subgraph "Worker Node"
        GPU["AMD GPU Hardware"]
        KMOD["amdgpu kernel module"]
    end

    NFD -->|"labels node<br/>amd-gpu=true"| DC
    DC -->|"watched by"| CTRL
    CTRL -->|"creates"| MOD
    CTRL -->|"deploys"| DRA
    CTRL -->|"deploys"| NL
    CTRL -->|"deploys"| ME
    CTRL -->|"deploys (if enabled)"| DP
    CTRL -->|"triggers (if enabled)"| ANR
    MOD -->|"triggers build"| KANIKO
    KANIKO -->|"pushes image to<br/>private registry"| DC_SECRET
    MOD -->|"triggers load"| WORKER
    WORKER -->|"modprobe"| KMOD
    DS -->|"configures containerd<br/>on every node"| WORKER
    KMOD --- GPU
```

### Driver Build Flow

```mermaid
sequenceDiagram
    participant NFD as NFD Worker
    participant Node as Worker Node
    participant Ctrl as GPU Operator Controller
    participant KMM as KMM Controller
    participant Kaniko as Kaniko Build Pod
    participant Reg as Private Registry
    participant Worker as KMM Worker Pod

    NFD->>Node: Detects AMD GPU, sets label amd-gpu=true
    Ctrl->>Ctrl: DeviceConfig selector matches node
    Ctrl->>KMM: Creates Module CR (driver image + build spec)
    KMM->>Kaniko: Spawns Kaniko pod for kernel version
    Kaniko->>Kaniko: Builds driver from OS base image + kernel headers
    Kaniko->>Reg: Pushes built driver image (tagged by kernel version)
    KMM->>Worker: Deploys worker pod on target node
    Worker->>Reg: Pulls driver image (via kmm-registry-dockerconfig)
    Worker->>Node: Runs modprobe to load amdgpu kernel module
    Ctrl->>Node: Deploys DRA driver + labeller + Metrics Exporter
```

## Dependencies

| Dependency | Purpose | Enforcement |
|---|---|---|
| `amd-kmm-operator` | Shared KMM instance + registry plumbing | `metadata.yaml` (`dependencies`) -- strongly recommended, not required |
| Node Feature Discovery | GPU hardware detection and labelling | Provided by Kommander platform layer |
| Argo Workflows v4.0.3 | Auto Node Remediation (optional) | Installed by chart when `remediation.enabled: true` |

## Default Configuration

The following subcharts are **disabled** by default because they are provided by other NKP components:

| Subchart | Disabled | Provided By |
|---|---|---|
| `kmm` | `kmm.enabled: false` | `amd-kmm-operator` |
| `node-feature-discovery` | `node-feature-discovery.enabled: false` | Kommander |
| `remediation` | `remediation.enabled: false` | Requires Argo Workflows — opt-in |

The chart auto-creates a `DeviceConfig` CR named `default` with:
- `spec.selector: { feature.node.kubernetes.io/amd-gpu: "true" }` (physical GPUs)
- `spec.driver.enable: true`
- DRA driver (default), Node Labeller, and Metrics Exporter
- Device Plugin disabled (mutually exclusive with DRA)

## New in v1.5.0

| Feature | Status | Notes |
|---|---|---|
| DRA Driver | **Enabled by default** | Replaces Device Plugin for GPU resource allocation; DRA is GA on K8s 1.35+ (NKP v2.18.0+), CDI in containerd 2.1+ |
| Auto Node Remediation (ANR) | Disabled by default | Argo Workflows-based GPU node recovery |
| Node Problem Detector (NPD) | Integration available | Requires separate NPD installation |
| `kmm.watch` parameter | Set to `true` | Independent control over KMM usage vs. installation |
| Global image pull secrets | Available | `global.imagePullSecrets` or `commonConfig.imageRegistrySecrets` |
| Custom package repos | Available | `imageBuild.packageRepoURL` / `gpgKeyURL` |
| New metrics | Active | `GPU_PROCESS_CU_OCCUPANCY`, `GPU_ECC_DEFERRED_*` |
| NFD subchart | v0.18.3 | Upgraded from v0.16.1 (disabled in NKP) |

## NFD Toleration Requirement

Kommander's NFD worker DaemonSet must include the following toleration to discover AMD GPUs on tainted nodes:

```yaml
tolerations:
  - key: "amd-dcm"
    operator: "Equal"
    value: "up"
    effect: "NoExecute"
```

Without this, NFD workers won't run on nodes with the `amd-dcm` taint, and those nodes won't receive AMD GPU feature labels.

## Node Feature Labels

The GPU Operator installs NFD rules that produce two labels. Each requires its own `DeviceConfig` CR:

| NFD Label | Meaning | Default CR |
|---|---|---|
| `feature.node.kubernetes.io/amd-gpu: "true"` | Physical GPU (PF) detected | `default` (auto-created) |
| `feature.node.kubernetes.io/amd-vgpu: "true"` | Virtual GPU (SR-IOV VF) detected | User must create a second `DeviceConfig` |

## Config Overrides (Private Registry)

When enabling this operator with a private registry, supply config overrides that align with the `kmm-registry-credentials` secret created for the AMD KMM Operator. Replace the registry host, port, and project with your values:

```yaml
deviceConfig:
  spec:
    driver:
      enable: true
      blacklist: true
      version: "30.30.3"
      image: "<registry-host>:<port>/<project>/amdgpu_kmod"
      imageBuild:
        baseImageRegistry: "<registry-host>:<port>/<project>"
        baseImageRegistryTLS:
          insecure: false
          insecureSkipTLSVerify: false
        packageRepoURL: ""   # optional: override repo.radeon.com for air-gapped environments
        gpgKeyURL: ""         # optional: override GPG key URL for air-gapped environments
      imageRegistrySecret:
        name: "kmm-registry-dockerconfig"
      imageRegistryTLS:
        insecure: false
        insecureSkipTLSVerify: false
    commonConfig:
      imageRegistrySecrets:
        - name: "kmm-registry-dockerconfig"   # injected into all operator-managed workloads
    draDriver:
      enable: true
      image: "docker.io/rocm/k8s-gpu-dra-driver:v1.0.0"
    devicePlugin:
      enableDevicePlugin: false
```

### Override Fields

| Field | Description |
|---|---|
| `driver.blacklist` | When `true`, unloads the in-tree `amdgpu` kernel module before loading the DKMS version. Required on nodes with a built-in `amdgpu` driver (most Ubuntu kernels). |
| `driver.version` | The amdgpu DKMS driver version to build (e.g. `30.30.3` for ROCm 7.2.1). See the [compatibility matrix](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/user-kernel-space-compat-matrix.html). |
| `driver.image` | Registry path where built GPU driver images are pushed/pulled. Do not include a tag; the operator manages tags automatically. |
| `driver.imageRegistrySecret.name` | Must be `kmm-registry-dockerconfig`, auto-created by the AMD KMM Operator reconciler. |
| `driver.imageBuild.baseImageRegistry` | Private mirror hosting OS base images (e.g. `ubuntu:24.04`) for Kaniko builds. Avoids Docker Hub rate limits. |
| `driver.imageBuild.packageRepoURL` | Override `repo.radeon.com` for air-gapped environments. |
| `driver.imageBuild.gpgKeyURL` | Override GPG key URL for air-gapped environments. |
| `driver.imageRegistryTLS.insecure` | Set `true` for plain HTTP registries. |
| `driver.imageRegistryTLS.insecureSkipTLSVerify` | Set `true` for self-signed certificates. |
| `commonConfig.imageRegistrySecrets` | Global pull secrets injected into all operator-managed workloads (DRA driver, Metrics Exporter, labeller, build pods, etc.). |
| `draDriver.enable` | Enables the DRA driver (default: `true`). Mutually exclusive with `devicePlugin.enableDevicePlugin`. |
| `draDriver.image` | DRA driver image. Override for private registry environments. |
| `devicePlugin.enableDevicePlugin` | Enables the traditional Device Plugin (default: `false`). Set `true` and `draDriver.enable: false` to revert to the legacy approach. |

### Credential Flow

```mermaid
graph LR
    A["kmm-registry-dockerconfig<br/>(auto-created by KMM Operator)"] -->|"referenced in"| B["DeviceConfig<br/>imageRegistrySecret"]
    B -->|"propagated to"| C["Module CR<br/>imageRepoSecret"]
    C -->|"injected into"| D["Kaniko Build Pod<br/>(push auth)"]
    C -->|"injected into"| E["KMM Worker Pod<br/>(pull auth)"]
```

## Install / Uninstall

**Install:** It is strongly recommended to enable `amd-kmm-operator` first, then `amd-gpu-operator`. Without a KMM instance, driver builds will not function.

**Uninstall:** Disable `amd-gpu-operator` first, then `amd-kmm-operator`.
