# NKP AI Applications Catalog — task runner
# Install just: https://github.com/casey/just
#
# Run `just` to list all recipes, or `just <recipe>` to run one.

set unstable

import 'just/tools.just'
import 'just/validate.just'
import 'just/release.just'

# Default: list available recipes
default:
    @just --list

# ---------- Scaffold ----------

# Generate the application scaffold for a new app
# Usage: just generate-app <appname> <version>
generate-app appname version: nkp-cli
  "{{ NKP_CLI }}" generate catalog-repository --apps={{ appname }}={{ version }}

# Pull a Helm chart, push to OCI, and generate the app scaffold — all in one
# Usage: just add-app <app> <repo-name> <repo-url> <chart> <version> <oci-registry>
add-app app repo-name repo-url chart version oci-registry:
    just push-helm-to-oci {{ app }} {{ repo-name }} {{ repo-url }} {{ chart }} {{ version }} {{ oci-registry }}
    just generate-app {{ app }} {{ version }}

# ---------- Checks ----------

# Run pre-commit hooks and gitlint
# SKIP=git-dirty: allow running with uncommitted changes (validation run, not commit)
pre-commit:
    env VIRTUALENV_PIP=24.0 pre-commit install-hooks
    env SKIP=git-dirty pre-commit run -a --show-diff-on-failure
    git fetch origin main
    pre-commit run --hook-stage manual gitlint-ci

# Quick check: pre-commit only (no nkp CLI needed)
check: pre-commit

# Full check: pre-commit + catalog validation (ready to push)
check-all: pre-commit validate

# Check if catalog apps have newer versions at source (Helm repo or OCI)
# Requires: helm, crane (for OCI apps). Usage: just check-versions [--json] [--app NAME]
check-versions *ARGS:
    ./scripts/check-app-versions.sh {{ ARGS }}

# ---------- OCI registry ----------

# Login to GHCR (reads .env.local)
login:
    ./scripts/login-oci-registry.sh

# ---------- Helm → OCI ----------

# Base OCI registry for Helm chart pushes. Override for testing:
#   OCI_REGISTRY=oci://my-registry.com/charts just push-ollama
OCI_REGISTRY := env_var_or_default('OCI_REGISTRY', 'oci://ghcr.io/nutanix-cloud-native/charts')

# Pull a Helm chart and push it to an OCI registry, then generate .catalog-source.yaml
# Usage: just push-helm-to-oci <app> <repo-name> <repo-url> <chart> <version> <oci-registry>
push-helm-to-oci app repo-name repo-url chart version oci-registry:
    ./scripts/push-helm-to-oci.sh {{app}} {{repo-name}} {{repo-url}} {{chart}} {{version}} {{oci-registry}}

# Shortcut: push ollama chart to OCI
push-ollama version="1.39.0" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci ollama ollama-helm https://otwld.github.io/ollama-helm/ ollama {{version}} {{oci-registry}}

# Shortcut: push ollama chart and generate scaffold in one step
add-ollama version="1.39.0" oci-registry=OCI_REGISTRY:
    just add-app ollama ollama-helm https://otwld.github.io/ollama-helm/ ollama {{version}} {{oci-registry}}

# Shortcut: push vllm chart to OCI
push-vllm version="0.1.1" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci vllm vllm https://open-source-ai-dev.github.io/vllm-helm-chart vllm {{version}} {{oci-registry}}

# Shortcut: push vllm chart and generate scaffold in one step
add-vllm version="0.1.1" oci-registry=OCI_REGISTRY:
    just add-app vllm vllm https://open-source-ai-dev.github.io/vllm-helm-chart vllm {{version}} {{oci-registry}}

# Shortcut: push open-webui chart to OCI
push-openwebui version="12.0.1" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci open-webui open-webui https://helm.openwebui.com/ open-webui {{version}} {{oci-registry}}

# Shortcut: push weaviate chart to OCI
push-weaviate version="17.7.0" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci weaviate weaviate https://weaviate.github.io/weaviate-helm/ weaviate {{version}} {{oci-registry}}

# Shortcut: push coder chart to OCI
push-coder version="2.30.2" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci coder coder-v2 https://helm.coder.com/v2 coder {{version}} {{oci-registry}}

# Shortcut: push mlflow chart to OCI
push-mlflow version="1.8.1" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci mlflow community-charts https://community-charts.github.io/helm-charts mlflow {{version}} {{oci-registry}}

# Shortcut: push flowise chart to OCI
push-flowise version="6.0.0" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci flowise cowboysysop https://cowboysysop.github.io/charts/ flowise {{version}} {{oci-registry}}

# Shortcut: push jupyterhub chart to OCI
push-jupyterhub version="4.3.2" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci jupyterhub jupyterhub https://hub.jupyter.org/helm-chart/ jupyterhub {{version}} {{oci-registry}}

# Shortcut: push milvus-operator chart to OCI
push-milvus-operator version="1.3.6" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci milvus-operator milvus-operator https://zilliztech.github.io/milvus-operator/ milvus-operator {{version}} {{oci-registry}}

# Shortcut: push langgraph chart to OCI
push-langgraph version="0.2.6" oci-registry=OCI_REGISTRY:
    just push-helm-to-oci langgraph langchain https://langchain-ai.github.io/helm/ langgraph-cloud {{version}} {{oci-registry}}

# ---------- Add App (push + generate) ----------

# Shortcut: push open-webui chart and generate scaffold in one step
add-openwebui version="12.0.1" oci-registry=OCI_REGISTRY:
    just add-app open-webui open-webui https://helm.openwebui.com/ open-webui {{version}} {{oci-registry}}

# Shortcut: push weaviate chart and generate scaffold in one step
add-weaviate version="17.7.0" oci-registry=OCI_REGISTRY:
    just add-app weaviate weaviate https://weaviate.github.io/weaviate-helm/ weaviate {{version}} {{oci-registry}}

# Shortcut: push coder chart and generate scaffold in one step
add-coder version="2.30.2" oci-registry=OCI_REGISTRY:
    just add-app coder coder-v2 https://helm.coder.com/v2 coder {{version}} {{oci-registry}}

# Shortcut: push mlflow chart and generate scaffold in one step
add-mlflow version="1.8.1" oci-registry=OCI_REGISTRY:
    just add-app mlflow community-charts https://community-charts.github.io/helm-charts mlflow {{version}} {{oci-registry}}

# Shortcut: push flowise chart and generate scaffold in one step
add-flowise version="6.0.0" oci-registry=OCI_REGISTRY:
    just add-app flowise cowboysysop https://cowboysysop.github.io/charts/ flowise {{version}} {{oci-registry}}

# Shortcut: push jupyterhub chart and generate scaffold in one step
add-jupyterhub version="4.3.2" oci-registry=OCI_REGISTRY:
    just add-app jupyterhub jupyterhub https://hub.jupyter.org/helm-chart/ jupyterhub {{version}} {{oci-registry}}

# Shortcut: push milvus-operator chart and generate scaffold in one step
add-milvus-operator version="1.3.6" oci-registry=OCI_REGISTRY:
    just add-app milvus-operator milvus-operator https://zilliztech.github.io/milvus-operator/ milvus-operator {{version}} {{oci-registry}}

# Shortcut: push langgraph chart and generate scaffold in one step
add-langgraph version="0.2.6" oci-registry=OCI_REGISTRY:
    just add-app langgraph langchain https://langchain-ai.github.io/helm/ langgraph-cloud {{version}} {{oci-registry}}

# ---------- Kubeflow Kustomize image mirroring ----------

# List container images from Kubeflow Kustomize apps (excludes kubeflow-pipelines)
list-kubeflow-images:
    ./scripts/mirror-kubeflow-images.sh --list-only

# Mirror Kubeflow Kustomize images to a registry (requires crane or docker)
# Usage: just mirror-kubeflow-images ghcr.io/deepak-muley
#        just mirror-kubeflow-images ghcr.io/deepak-muley katib
mirror-kubeflow-images registry app="":
    bash -c 'if [ -n "{{app}}" ]; then ./scripts/mirror-kubeflow-images.sh --push {{registry}} --app {{app}}; else ./scripts/mirror-kubeflow-images.sh --push {{registry}}; fi'
