{{- define "ccf-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ccf-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "ccf-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ccf-agent.labels" -}}
helm.sh/chart: {{ include "ccf-agent.chart" . }}
{{ include "ccf-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ccf
app.kubernetes.io/component: agent
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "ccf-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ccf-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ccf-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ccf-agent.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolved API URL: explicit config.api.url wins, otherwise .Values.apiUrl.
*/}}
{{- define "ccf-agent.apiUrl" -}}
{{- if .Values.config.api.url -}}
{{- .Values.config.api.url -}}
{{- else -}}
{{- required "Set agent apiUrl (or config.api.url) to the CCF API endpoint" .Values.apiUrl -}}
{{- end -}}
{{- end }}
