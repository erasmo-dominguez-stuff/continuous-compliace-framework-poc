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

{{/*
Resolved image registry prefix.
*/}}
{{- define "ccf-agent.images.registry" -}}
{{- if and .Values.global .Values.global.images -}}
{{- coalesce .Values.global.images.registry .Values.global.images.registryPrefix .Values.images.registry .Values.images.registryPrefix "ghcr.io/compliance-framework" -}}
{{- else -}}
{{- coalesce .Values.images.registry .Values.images.registryPrefix "ghcr.io/compliance-framework" -}}
{{- end -}}
{{- end }}

{{- define "ccf-agent.images.registryPrefix" -}}
{{- include "ccf-agent.images.registry" . -}}
{{- end }}

{{- define "ccf-agent.images.defaultPrefix" -}}
{{- coalesce .Values.images.pluginRegistry "ghcr.io/compliance-framework" -}}
{{- end }}

{{- define "ccf-agent.image.pullPolicy" -}}
{{- coalesce .image.pullPolicy .root.Values.images.pullPolicy "IfNotPresent" -}}
{{- end }}

{{- define "ccf-agent.image.ref" -}}
{{- $root := .root -}}
{{- $image := .image -}}
{{- $cfg := $root.Values.images.agent | default dict -}}
{{- $registry := include "ccf-agent.images.registry" $root -}}
{{- $repoPart := coalesce $image.repository $cfg.repository "agent" -}}
{{- $repo := ternary $repoPart (printf "%s/%s" $registry $repoPart) (contains "/" $repoPart) -}}
{{- $tag := coalesce $image.tag $cfg.tag $root.Chart.AppVersion -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end }}

{{/*
Rewrite an OCI reference when mirroring to a private registry.
*/}}
{{- define "ccf-agent.rewriteOci" -}}
{{- $ref := .ref -}}
{{- $from := .from -}}
{{- $to := .to -}}
{{- if and $to $from (ne $from $to) (hasPrefix $from $ref) -}}
{{- printf "%s%s" $to (trimPrefix $from $ref) -}}
{{- else -}}
{{- $ref -}}
{{- end -}}
{{- end }}

{{/*
Agent config with plugin/policy OCI refs rewritten for global.images.registryPrefix.
*/}}
{{- define "ccf-agent.resolvedConfigYaml" -}}
{{- $config := deepCopy .Values.config -}}
{{- $from := include "ccf-agent.images.defaultPrefix" . -}}
{{- $to := include "ccf-agent.images.registryPrefix" . -}}
{{- range $name, $plugin := $config.plugins -}}
{{- if $plugin.source -}}
{{- $_ := set $plugin "source" (include "ccf-agent.rewriteOci" (dict "ref" $plugin.source "from" $from "to" $to)) -}}
{{- end -}}
{{- $policies := default list $plugin.policies -}}
{{- $newPolicies := list -}}
{{- range $p := $policies -}}
{{- if kindIs "string" $p -}}
{{- $newPolicies = append $newPolicies (include "ccf-agent.rewriteOci" (dict "ref" $p "from" $from "to" $to)) -}}
{{- else if $p.source -}}
{{- $_ := set $p "source" (include "ccf-agent.rewriteOci" (dict "ref" $p.source "from" $from "to" $to)) -}}
{{- $newPolicies = append $newPolicies $p -}}
{{- else -}}
{{- $newPolicies = append $newPolicies $p -}}
{{- end -}}
{{- end -}}
{{- $_ := set $plugin "policies" $newPolicies -}}
{{- end -}}
{{- $apiUrl := include "ccf-agent.apiUrl" . -}}
{{- $config = mergeOverwrite $config (dict "api" (dict "url" $apiUrl)) -}}
{{- toYaml $config -}}
{{- end }}

{{- define "ccf-agent.imagePullSecrets" -}}
{{- if .Values.images.pullSecrets -}}
{{- toYaml .Values.images.pullSecrets -}}
{{- else -}}
{{- toYaml (.Values.imagePullSecrets | default list) -}}
{{- end -}}
{{- end }}
