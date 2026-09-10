# flowise

Drag-and-drop UI to build and deploy LLM workflows and agents with LangChain.

## Chart Source

The Flowise Helm chart is published natively as an OCI artifact.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nutanix-cloud-native/charts/flowise:1.3.4` |
| Version | `1.3.4` |

The catalog entry references this chart in `helmrelease/helmrelease.yaml`.

## Default Configuration

The default values in `helmrelease/cm.yaml` are intentionally empty. This means
the chart's upstream defaults are used unless values are provided through NKP
app configuration (`configOverrides`) or by editing `helmrelease/cm.yaml`.

## Validation

The application uses the version-local `.bloodhound.yml` generated scaffold for
manifest validation settings.

## Links

- [Flowise Docs](https://docs.flowiseai.com/)
- [Flowise GitHub](https://github.com/FlowiseAI/Flowise)
