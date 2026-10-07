# kfp-tutorial-runtime

Catalog-owned component image for Kubeflow Pipelines UI tutorials. Ships
`kfp==2.14.3` (with dependencies) on `python:3.9-slim` so air-gapped tutorial
runs never call PyPI.

## Image

`ghcr.io/nutanix-cloud-native/kfp-tutorial-runtime:2.15.0`

Tag tracks the Kubeflow Pipelines catalog app version (2.15.0), not the kfp
SDK pin (2.14.3).

## Build locally

```bash
docker build -t ghcr.io/nutanix-cloud-native/kfp-tutorial-runtime:2.15.0 \
  images/kfp-tutorial-runtime
```

Publish this image to GHCR **before** airgap bundles are cut. This README does
not push; someone with registry access must publish the tag above so IRM/airgap
mirroring can pull it.

## Consumers

Rewritten tutorial pipeline YAMLs under
`overlays/kubeflow-pipelines/airgap-tutorials/samples/` reference this image.
See that overlay's README for ConfigMap mount and upgrade notes.
