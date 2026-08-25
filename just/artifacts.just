# Package a bake-generated chart (charts/<app>, produced by `just bake <app>`)
# and push it to our OCI registry. Login first with `just login`.
# Usage: just push-baked-chart kubeflow-central-dashboard [oci-registry]
push-baked-chart app oci-registry=OCI_REGISTRY:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ app }}" in
      kubeflow-pipelines|kubeflow-central-dashboard) ;;
      *)
        echo "push-baked-chart only accepts kubeflow-pipelines or kubeflow-central-dashboard" >&2
        exit 1
        ;;
    esac
    [ -f "charts/{{ app }}/Chart.yaml" ] || { echo "No chart at charts/{{ app }}; run 'just bake {{ app }}' first" >&2; exit 1; }
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' EXIT
    echo "==> Packaging charts/{{ app }}"
    helm package "charts/{{ app }}" -d "$workdir"
    echo "==> Pushing to {{ oci-registry }}"
    helm push "$workdir"/*.tgz {{ oci-registry }}

# Run bake tool Go module from tools/bake; artifacts land in repo root.
GO_BAKE := 'go -C tools/bake'
BAKE := GO_BAKE + ' run .'

# Render and bake an app's manifest into its helmrelease/ directory.
# Usage: just bake <app> [version]
bake app version="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ version }}" ]; then
      {{ BAKE }} --app "{{ app }}" --version "{{ version }}"
    else
      {{ BAKE }} --app "{{ app }}"
    fi

# Re-bake all apps and fail if committed artifacts have drifted.
bake-check:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ BAKE }} --all
    if ! git diff --exit-code -- applications/ charts/; then
      echo "::error::Baked artifacts are stale. Run 'just bake <app> [version]' and commit the result." >&2
      exit 1
    fi

# Compile-check the bake tool without creating a binary.
bake-build:
    {{ GO_BAKE }} build -o /dev/null ./...

# Vet and unit-test the bake tool.
bake-test:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ GO_BAKE }} vet ./...
    {{ GO_BAKE }} test ./...
