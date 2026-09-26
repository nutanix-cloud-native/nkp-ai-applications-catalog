{{- define "amd-resource-manager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "amd-resource-manager.labels" -}}
app.kubernetes.io/name: {{ include "amd-resource-manager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
airm.nutanix.com/mode: {{ .Values.airm.mode | quote }}
{{- end -}}

{{- define "amd-resource-manager.catalogSourceName" -}}
{{- .Values.catalog.sourceName | default "REPLACE_AT_INSTALL" -}}
{{- end -}}

{{- define "amd-resource-manager.catalogSourceNamespace" -}}
{{- .Values.catalog.sourceNamespace | default .Release.Namespace -}}
{{- end -}}

{{- define "amd-resource-manager.releaseNamespace" -}}
{{- default .Release.Namespace .Values.catalog.releaseNamespace -}}
{{- end -}}

{{- define "amd-resource-manager.stageKustomizationName" -}}
{{- printf "%s-%s" (default .Values.catalog.releaseName .Release.Name) .stage | trunc 63 | trimSuffix "-" -}}
{{- end -}}

