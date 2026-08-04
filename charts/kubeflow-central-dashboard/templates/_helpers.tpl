{{/*
Renders a dashboard externalLink for JupyterHub ("iframe": false, so it opens in a
new tab where its own Dex login works - it can't be embedded/proxied). Returns one
JSON object when JupyterHub is installed, else "". Scheme/host come from JupyterHub's
own Ingress, falling back to the LB address then kommander-vars.ingressAddress.

NOTE: hand-authored on the baked chart; re-apply on re-bake (helper + the templated
externalLinks slot).
*/}}
{{- define "kubeflow-central-dashboard.jupyterhubExternalLink" -}}
{{- $ns := "jupyterhub" -}}
{{- if lookup "v1" "Service" $ns "jupyterhub-proxy-public" -}}
{{- $scheme := "http" -}}
{{- $host := "" -}}
{{- $ing := lookup "networking.k8s.io/v1" "Ingress" $ns "jupyterhub" -}}
{{- if $ing -}}
{{- if $ing.spec.tls -}}{{- $scheme = "https" -}}{{- end -}}
{{- with $ing.spec.rules -}}{{- with (index . 0).host -}}{{- if ne . "*" -}}{{- $host = . -}}{{- end -}}{{- end -}}{{- end -}}
{{- if not $host -}}{{- with $ing.status.loadBalancer.ingress -}}{{- with (index . 0) -}}{{- $host = (.ip | default .hostname) -}}{{- end -}}{{- end -}}{{- end -}}
{{- end -}}
{{- if not $host -}}{{- $kv := lookup "v1" "ConfigMap" "kommander" "kommander-vars" -}}{{- if $kv -}}{{- $host = (index $kv.data "ingressAddress") -}}{{- end -}}{{- end -}}
{{- if $host -}}
{{- printf `{"type":"item","iframe":false,"text":"Notebooks (JupyterHub)","link":"%s://%s/jupyter/","icon":"book"}` $scheme $host -}}
{{- end -}}
{{- end -}}
{{- end -}}
