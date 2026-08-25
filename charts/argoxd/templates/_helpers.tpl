{{/*
Expand the name of the chart.
*/}}
{{- define "argoxd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "argoxd.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "argoxd.labels" -}}
helm.sh/chart: {{ include "argoxd.name" . }}-{{ .Chart.Version }}
{{ include "argoxd.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "argoxd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "argoxd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
