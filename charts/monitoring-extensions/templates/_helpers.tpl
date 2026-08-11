{{/*
Chart name, overridable.
*/}}
{{- define "monitoring-extensions.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified release name.
*/}}
{{- define "monitoring-extensions.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Target namespace. Defaults to the release namespace; never assumes `monitoring`
(spec §5.3).
*/}}
{{- define "monitoring-extensions.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{/*
Standard labels. Chart.Version carries a `+` for build metadata in some tooling,
which is not a legal label value, so it is replaced.
*/}}
{{- define "monitoring-extensions.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "monitoring-extensions.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kube-prometheus-stack
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Turn a dashboard file path into a DNS-1123 ConfigMap name segment:
`dashboards/app-workloads.json` -> `app-workloads`.
*/}}
{{- define "monitoring-extensions.dashboardName" -}}
{{- . | base | trimSuffix ".json" | lower | replace "_" "-" | replace " " "-" -}}
{{- end -}}
