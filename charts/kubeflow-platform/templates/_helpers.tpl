{{- define "kubeflow-platform.fullname" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolves the integration config once so every consumer sees the same values.
Per field: .Values.config override -> value persisted from a prior render ->
derived from the cluster or generated. Offline (lint/template) lookups are empty,
so callers guard cluster-only assertions on liveness.
*/}}
{{- define "kubeflow-platform.derived" -}}
{{- $cfg := .Values.config -}}
{{- $dexIssuer := $cfg.dexIssuerURL -}}
{{- if not $dexIssuer -}}
{{- $kv := lookup "v1" "ConfigMap" "kommander" "kommander-vars" -}}
{{- if $kv -}}{{- with (index $kv.data "ingressAddress") -}}{{- $dexIssuer = printf "https://%s/dex" . -}}{{- end -}}{{- end -}}
{{- end -}}
{{- $ingressHost := $cfg.kubeflowIngressHost -}}
{{- $svcNamespace := $cfg.ingressGatewayNamespace -}}
{{- $svcName := $cfg.ingressGatewayService -}}
{{- $ingressGatewayPrincipal := $cfg.ingressGatewayPrincipal -}}
{{- if .Values.dedicatedIngress.enabled -}}
{{- $svcNamespace = .Release.Namespace -}}
{{- $svcName = .Values.dedicatedIngress.serviceName -}}
{{- if not $ingressGatewayPrincipal -}}
{{- $ingressGatewayPrincipal = printf "cluster.local/ns/%s/sa/%s" .Release.Namespace .Values.dedicatedIngress.serviceName -}}
{{- end -}}
{{- end -}}
{{- if not $ingressHost -}}
{{- $svc := lookup "v1" "Service" $svcNamespace $svcName -}}
{{- if $svc -}}{{- with $svc.status.loadBalancer.ingress -}}{{- with (index . 0) -}}{{- $ingressHost = (.ip | default .hostname) -}}{{- end -}}{{- end -}}{{- end -}}
{{- end -}}
{{- if and (not $ingressGatewayPrincipal) $svcNamespace $svcName -}}
{{- $ingressGatewayPrincipal = printf "cluster.local/ns/%s/sa/%s" $svcNamespace $svcName -}}
{{- end -}}
{{- $ingressURL := $cfg.kubeflowIngressURL -}}
{{- if and (not $ingressURL) $ingressHost -}}{{- $ingressURL = printf "http://%s" $ingressHost -}}{{- end -}}
{{- $prev := lookup "v1" "Secret" .Release.Namespace "kubeflow-platform-generated" -}}
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
