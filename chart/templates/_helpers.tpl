{{/* 生成 chart 名称 */}}
{{- define "claude-agent-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 生成完整的资源名称 */}}
{{- define "claude-agent-api.fullname" -}}
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

{{/* 生成 chart 标签 */}}
{{- define "claude-agent-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 通用标签 */}}
{{- define "claude-agent-api.labels" -}}
helm.sh/chart: {{ include "claude-agent-api.chart" . }}
{{ include "claude-agent-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* 选择器标签 */}}
{{- define "claude-agent-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "claude-agent-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
