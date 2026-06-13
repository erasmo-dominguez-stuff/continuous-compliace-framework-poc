{{/*
Expand the name of the chart.
*/}}
{{- define "ccf.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ccf.fullname" -}}
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

{{/*
Chart label.
*/}}
{{- define "ccf.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "ccf.labels" -}}
helm.sh/chart: {{ include "ccf.chart" . }}
app.kubernetes.io/name: {{ include "ccf.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ccf
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for a component. Call with: (dict "ctx" . "component" "api")
*/}}
{{- define "ccf.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ccf.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Labels for a component. Call with: (dict "ctx" . "component" "api")
*/}}
{{- define "ccf.componentLabels" -}}
{{ include "ccf.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "ccf.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ccf.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Component fully qualified names.
*/}}
{{- define "ccf.postgres.fullname" -}}{{ printf "%s-postgres" (include "ccf.fullname" .) | trunc 63 | trimSuffix "-" }}{{- end }}
{{- define "ccf.api.fullname" -}}{{ printf "%s-api" (include "ccf.fullname" .) | trunc 63 | trimSuffix "-" }}{{- end }}
{{- define "ccf.ui.fullname" -}}{{ printf "%s-ui" (include "ccf.fullname" .) | trunc 63 | trimSuffix "-" }}{{- end }}

{{/*
Database host used by the API.
*/}}
{{- define "ccf.db.host" -}}
{{- if .Values.postgres.enabled -}}
{{- include "ccf.postgres.fullname" . -}}
{{- else -}}
{{- required "api.database.host is required when postgres.enabled is false" .Values.api.database.host -}}
{{- end -}}
{{- end }}

{{/*
Full PostgreSQL connection string for the API.
*/}}
{{- define "ccf.db.connection" -}}
{{- if .Values.api.database.connection -}}
{{- .Values.api.database.connection -}}
{{- else if and .Values.postgres.enabled .Values.postgres.auth.existingSecret -}}
{{- fail "postgres.auth.existingSecret is set but the API connection password is unknown. Set api.database.connection or api.database.existingSecret (a Secret with key CCF_DB_CONNECTION)." -}}
{{- else -}}
{{- printf "host=%s user=%s password=%s dbname=%s port=%v sslmode=%s" (include "ccf.db.host" .) .Values.postgres.auth.username .Values.postgres.auth.password .Values.postgres.auth.database (.Values.postgres.service.port | toString) .Values.api.database.sslmode -}}
{{- end -}}
{{- end }}

{{/*
URL of the API as reachable from the browser (used by the UI).
*/}}
{{- define "ccf.ui.apiUrl" -}}
{{- if .Values.ui.apiUrl -}}
{{- .Values.ui.apiUrl -}}
{{- else if and .Values.ingress.enabled .Values.ingress.apiHost -}}
{{- $scheme := ternary "https" "http" (gt (len .Values.ingress.tls) 0) -}}
{{- printf "%s://%s" $scheme .Values.ingress.apiHost -}}
{{- else -}}
{{- printf "http://localhost:%v" .Values.api.service.port -}}
{{- end -}}
{{- end }}

{{/*
API allowed origins (browser CORS).
*/}}
{{- define "ccf.api.allowedOrigins" -}}
{{- if .Values.api.allowedOrigins -}}
{{- .Values.api.allowedOrigins -}}
{{- else if and .Values.ingress.enabled .Values.ingress.uiHost -}}
{{- $scheme := ternary "https" "http" (gt (len .Values.ingress.tls) 0) -}}
{{- printf "%s://%s" $scheme .Values.ingress.uiHost -}}
{{- else -}}
{{- "http://localhost:3000,http://localhost:8000" -}}
{{- end -}}
{{- end }}

{{/*
Prometheus scrape annotations for the API pods.
*/}}
{{- define "ccf.api.podAnnotations" -}}
{{- $annotations := dict -}}
{{- if .Values.api.metrics.enabled -}}
{{- $_ := set $annotations "prometheus.io/scrape" "true" -}}
{{- $_ := set $annotations "prometheus.io/port" (.Values.api.metrics.port | toString) -}}
{{- $_ := set $annotations "prometheus.io/path" .Values.api.metrics.path -}}
{{- end -}}
{{- $annotations = merge $annotations .Values.api.podAnnotations -}}
{{- toYaml $annotations -}}
{{- end }}

{{/*
In-cluster API service DNS name (used by external consumers like the agent).
*/}}
{{- define "ccf.api.serviceUrl" -}}
{{- printf "http://%s:%v" (include "ccf.api.fullname" .) .Values.api.service.port -}}
{{- end }}

{{/*
envFrom block (config + DB/JWT secrets) shared by the API deployment and the
admin/seed Jobs. Render with `{{- include "ccf.api.envFrom" . | nindent N }}`.
*/}}
{{- define "ccf.api.envFrom" -}}
- configMapRef:
    name: {{ include "ccf.api.fullname" . }}
{{- if or (not .Values.api.database.existingSecret) .Values.api.jwtSecret }}
- secretRef:
    name: {{ include "ccf.api.fullname" . }}
{{- end }}
{{- if .Values.api.database.existingSecret }}
- secretRef:
    name: {{ .Values.api.database.existingSecret }}
{{- end }}
{{- end }}
