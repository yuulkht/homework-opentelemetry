{{/*
Расширяет имя chart'а
*/}}
{{- define "muffin-wallet.name" -}}
{{- default .Chart.Name .Values.common.resources.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Создает полное имя приложения по умолчанию
*/}}
{{- define "muffin-wallet.fullname" -}}
{{- if .Values.common.resources.fullnameOverride -}}
{{- .Values.common.resources.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.common.resources.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Создает имя и версию chart'а для использования в метках
*/}}
{{- define "muffin-wallet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Общие метки для всех ресурсов
*/}}
{{- define "muffin-wallet.labels" -}}
helm.sh/chart: {{ include "muffin-wallet.chart" . }}
{{ include "muffin-wallet.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Селекторные метки для выбора Pod'ов
*/}}
{{- define "muffin-wallet.selectorLabels" -}}
app.kubernetes.io/name: {{ include "muffin-wallet.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}