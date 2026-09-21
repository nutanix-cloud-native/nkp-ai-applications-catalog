{{/*
Renders a dashboard externalLink for JupyterHub ("iframe": false, so it opens in a
new tab where its own Dex login works - it can't be embedded/proxied). Returns one
JSON object when JupyterHub is installed, else "". Scheme/host come from JupyterHub's
own Ingress, falling back to the LB address then kommander-vars.ingressAddress.

NOTE: hand-authored on the baked chart; re-apply on re-bake (helper + the templated
externalLinks slot).
*/}}
{{- define "kubeflow-central-dashboard.jupyterhubExternalLink" -}}
{{- $host := "" -}}
{{- $kv := lookup "v1" "ConfigMap" "kommander" "kommander-vars" -}}
{{- if $kv -}}
{{- $host = (index $kv.data "ingressAddress") -}}
{{- end -}}
{{- if $host -}}
{{- printf `{"type":"item","iframe":false,"text":"Notebooks (JupyterHub)","link":"https://%s/nkp/jupyter/","icon":"book"}` $host -}}
{{- end -}}
{{- end -}}
