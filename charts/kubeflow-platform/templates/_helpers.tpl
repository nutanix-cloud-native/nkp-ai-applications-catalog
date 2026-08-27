{{- define "kubeflow-platform.fullname" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolves the integration config once so every consumer sees the same values.
Per field: .Values.config override -> value persisted from a prior render ->
derived (Dex issuer, http://<host> URL) or generated (OIDC secrets).
kubeflowIngressHost is operator-set and is not looked up from a Service.
*/}}
{{- define "kubeflow-platform.derived" -}}
{{- $cfg := .Values.config -}}
{{- $platformNamespace := "kubeflow" -}}
{{- $dexIssuer := $cfg.dexIssuerURL -}}
{{- if not $dexIssuer -}}
{{- $kv := lookup "v1" "ConfigMap" "kommander" "kommander-vars" -}}
{{- if $kv -}}{{- with (index $kv.data "ingressAddress") -}}{{- $dexIssuer = printf "https://%s/dex" . -}}{{- end -}}{{- end -}}
{{- end -}}
{{- $ingressHost := $cfg.kubeflowIngressHost -}}
{{- $ingressGatewayPrincipal := $cfg.ingressGatewayPrincipal -}}
{{- if .Values.dedicatedIngress.enabled -}}
{{- if not $ingressGatewayPrincipal -}}
{{- $ingressGatewayPrincipal = printf "cluster.local/ns/%s/sa/%s" $platformNamespace .Values.dedicatedIngress.serviceName -}}
{{- end -}}
{{- end -}}
{{- if and (not $ingressGatewayPrincipal) .Values.config.ingressGatewayNamespace .Values.config.ingressGatewayService -}}
{{- $ingressGatewayPrincipal = printf "cluster.local/ns/%s/sa/%s" .Values.config.ingressGatewayNamespace .Values.config.ingressGatewayService -}}
{{- end -}}
{{- $ingressURL := $cfg.kubeflowIngressURL -}}
{{- if and (not $ingressURL) $ingressHost -}}{{- $ingressURL = printf "http://%s" $ingressHost -}}{{- end -}}
{{- $prev := lookup "v1" "Secret" $platformNamespace "kubeflow-platform-generated" -}}
{{- if and (not $prev) (ne .Release.Namespace $platformNamespace) -}}
{{- $prev = lookup "v1" "Secret" .Release.Namespace "kubeflow-platform-generated" -}}
{{- end -}}
{{- $client := $cfg.oauth2ClientSecret -}}
{{- if and (not $client) $prev -}}{{- with (index $prev.data "oauth2ClientSecret") -}}{{- $client = b64dec . -}}{{- end -}}{{- end -}}
{{- if not $client -}}{{- $client = randAlphaNum 48 -}}{{- end -}}
{{- $cookie := $cfg.oauth2CookieSecret -}}
{{- if and (not $cookie) $prev -}}{{- with (index $prev.data "oauth2CookieSecret") -}}{{- $cookie = b64dec . -}}{{- end -}}{{- end -}}
{{- if not $cookie -}}{{- $cookie = randAlphaNum 32 -}}{{- end -}}
dexIssuerURL: {{ $dexIssuer | quote }}
kubeflowIngressURL: {{ $ingressURL | quote }}
kubeflowIngressHost: {{ $ingressHost | quote }}
ingressGatewayPrincipal: {{ $ingressGatewayPrincipal | quote }}
oauth2ClientSecret: {{ $client | quote }}
oauth2CookieSecret: {{ $cookie | quote }}
{{- end -}}
