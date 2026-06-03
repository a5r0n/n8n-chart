{{/*
Expand the name of the chart.
*/}}
{{- define "n8n.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "n8n.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "n8n.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "n8n.labels" -}}
helm.sh/chart: {{ include "n8n.chart" . }}
{{ include "n8n.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "n8n.selectorLabels" -}}
app.kubernetes.io/name: {{ include "n8n.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "n8n.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "n8n.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the chart-managed Secret (encryption key + basic-auth password).
*/}}
{{- define "n8n.secretName" -}}
{{- include "n8n.fullname" . -}}
{{- end }}

{{/* ---------------------------- PostgreSQL ---------------------------- */}}
{{/* Service/Secret name of the bundled CloudPirates subchart. The subchart is
     aliased "postgresql", so its fullname resolves to "<release>-postgresql"
     (cloudpirates.fullname = "<release>-<alias>"). Must match exactly or the
     n8n pods reference a Secret/Service that does not exist. */}}
{{- define "n8n.pg.fullname" -}}
{{- .Values.postgresql.fullnameOverride | default (printf "%s-postgresql" .Release.Name) -}}
{{- end }}
{{- define "n8n.pg.host" -}}
{{- if .Values.postgresql.enabled -}}{{- include "n8n.pg.fullname" . -}}{{- else -}}{{- .Values.postgresql.external.host -}}{{- end -}}
{{- end }}
{{- define "n8n.pg.port" -}}
{{- if .Values.postgresql.enabled -}}5432{{- else -}}{{- .Values.postgresql.external.port | default 5432 -}}{{- end -}}
{{- end }}
{{- define "n8n.pg.database" -}}
{{- if .Values.postgresql.enabled -}}{{- .Values.postgresql.auth.database -}}{{- else -}}{{- .Values.postgresql.external.database -}}{{- end -}}
{{- end }}
{{- define "n8n.pg.username" -}}
{{- if .Values.postgresql.enabled -}}{{- .Values.postgresql.auth.username -}}{{- else -}}{{- .Values.postgresql.external.username -}}{{- end -}}
{{- end }}
{{- define "n8n.pg.passwordSecretName" -}}
{{- if .Values.postgresql.enabled -}}{{- .Values.postgresql.auth.existingSecret | default (include "n8n.pg.fullname" .) -}}{{- else -}}{{- .Values.postgresql.external.existingSecret -}}{{- end -}}
{{- end }}
{{- define "n8n.pg.passwordSecretKey" -}}
{{- if .Values.postgresql.enabled -}}
{{- if .Values.postgresql.auth.existingSecret -}}{{- .Values.postgresql.auth.secretKeys.adminPasswordKey | default "postgres-password" -}}{{- else -}}postgres-password{{- end -}}
{{- else -}}{{- .Values.postgresql.external.existingSecretPasswordKey | default "postgres-password" -}}{{- end -}}
{{- end }}

{{/* ------------------------------ Valkey ------------------------------ */}}
{{/* Service host of the bundled valkey-io subchart (release-valkey). */}}
{{- define "n8n.valkey.fullname" -}}
{{- .Values.valkey.fullnameOverride | default (printf "%s-valkey" .Release.Name) -}}
{{- end }}
{{- define "n8n.valkey.host" -}}
{{- if .Values.valkey.enabled -}}{{- include "n8n.valkey.fullname" . -}}{{- else -}}{{- .Values.valkey.external.host -}}{{- end -}}
{{- end }}
{{- define "n8n.valkey.port" -}}
{{- if .Values.valkey.enabled -}}6379{{- else -}}{{- .Values.valkey.external.port | default 6379 -}}{{- end -}}
{{- end }}
{{- define "n8n.valkey.database" -}}
{{- if .Values.valkey.enabled -}}0{{- else -}}{{- .Values.valkey.external.database | default "0" -}}{{- end -}}
{{- end }}
{{/* True (non-empty) when a Valkey password Secret should be wired in. */}}
{{- define "n8n.valkey.hasPassword" -}}
{{- if .Values.valkey.enabled -}}
{{- if .Values.valkey.auth.enabled -}}true{{- end -}}
{{- else -}}
{{- if .Values.valkey.external.existingSecret -}}true{{- end -}}
{{- end -}}
{{- end }}
{{- define "n8n.valkey.passwordSecretName" -}}
{{- if .Values.valkey.enabled -}}
{{- include "n8n.valkey.fullname" . -}}
{{- else -}}
{{- .Values.valkey.external.existingSecret -}}
{{- end -}}
{{- end }}
{{- define "n8n.valkey.passwordSecretKey" -}}
{{- .Values.valkey.external.existingSecretPasswordKey | default "redis-password" -}}
{{- end }}

{{/* -------------------------- Encryption key -------------------------- */}}
{{/* True when the encryption key comes from a user-provided existing Secret. */}}
{{- define "n8n.encryptionKey.fromExisting" -}}
{{- if .Values.n8n.existingSecret -}}true{{- end -}}
{{- end }}
{{- define "n8n.encryptionKey.secretName" -}}
{{- .Values.n8n.existingSecret -}}
{{- end }}
{{- define "n8n.encryptionKey.secretKey" -}}
{{- .Values.n8n.existingSecretKey | default "encryption-key" -}}
{{- end }}

{{/* ----------------------------- Validation --------------------------- */}}
{{- define "n8n.validate" -}}
{{- if .Values.redis -}}
{{- fail "The 'redis' values key was renamed to 'valkey' in chart 0.5.0. Move your redis.* settings under valkey.* (use valkey.external.* for an external instance)." -}}
{{- end -}}
{{- if and .Values.postgresql.enabled (not .Values.postgresql.auth.existingSecret) -}}
{{- $existingPgSecret := (lookup "v1" "Secret" .Release.Namespace (include "n8n.pg.fullname" .)) -}}
{{- if and $existingPgSecret (index $existingPgSecret.data "password") -}}
{{- fail "Detected an existing Bitnami PostgreSQL Secret. A plain helm upgrade will not work — the Bitnami and CloudPirates subcharts use incompatible password keys. See the '0.5.0 migration guide' section in the README. Easiest fix: set postgresql.auth.existingSecret=<release>-postgresql and postgresql.auth.secretKeys.adminPasswordKey=password to reuse the old Secret in-place." -}}
{{- end -}}
{{- end -}}
{{- if not (or (eq .Values.n8n.executionMode "queue") (eq .Values.n8n.executionMode "regular")) -}}
{{- fail (printf "n8n.executionMode must be 'queue' or 'regular', got %q" .Values.n8n.executionMode) -}}
{{- end -}}
{{- if and (not .Values.n8n.existingSecret) (not .Values.n8n.encryptionKey) -}}
{{- fail "Set n8n.encryptionKey (the chart creates a Secret) or n8n.existingSecret (a Secret you pre-created). The encryption key protects all stored credentials." -}}
{{- end -}}
{{- if and (not .Values.postgresql.enabled) (not .Values.postgresql.external.host) -}}
{{- fail "postgresql.enabled=false requires postgresql.external.host (and postgresql.external.existingSecret for the password)." -}}
{{- end -}}
{{- if and (not .Values.postgresql.enabled) .Values.postgresql.external.host (not .Values.postgresql.external.existingSecret) -}}
{{- fail "postgresql.external.existingSecret is required when postgresql.enabled=false (the chart needs a Secret to source the DB password from)." -}}
{{- end -}}
{{- if and (eq .Values.n8n.executionMode "queue") (not .Values.valkey.enabled) (not .Values.valkey.external.host) -}}
{{- fail "queue execution mode requires Valkey: set valkey.enabled=true or valkey.external.host, or switch n8n.executionMode to 'regular'." -}}
{{- end -}}
{{- end }}

{{/* -------------------- Container env wiring -------------------------- */}}
{{/* envFrom: non-secret config + the chart-managed Secret (encryption key /
     basic-auth password). secretRef is optional so it is harmless when the
     Secret isn't rendered (e.g. encryption key provided via existingSecret). */}}
{{- define "n8n.envFrom" -}}
- configMapRef:
    name: {{ include "n8n.fullname" . }}
- secretRef:
    name: {{ include "n8n.secretName" . }}
    optional: true
{{- end }}

{{/* Explicit env sourced from foreign Secrets (existing-secret encryption key,
     DB password, external Valkey password). */}}
{{- define "n8n.secretEnv" -}}
{{- if eq (include "n8n.encryptionKey.fromExisting" .) "true" }}
- name: N8N_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "n8n.encryptionKey.secretName" . }}
      key: {{ include "n8n.encryptionKey.secretKey" . }}
{{- end }}
- name: DB_POSTGRESDB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "n8n.pg.passwordSecretName" . }}
      key: {{ include "n8n.pg.passwordSecretKey" . }}
{{- if and (eq .Values.n8n.executionMode "queue") (eq (include "n8n.valkey.hasPassword" .) "true") }}
- name: QUEUE_BULL_REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "n8n.valkey.passwordSecretName" . }}
      key: {{ include "n8n.valkey.passwordSecretKey" . }}
{{- end }}
{{- end }}

{{/* Pod annotation that rolls the deployments when relevant config changes.
     Hashes the value subtrees that feed the ConfigMap/Secret (kept portable so
     it also renders under helm-unittest, which can't include sibling templates). */}}
{{- define "n8n.checksumAnnotations" -}}
checksum/config: {{ printf "%s|%s|%s|%s" (toJson .Values.n8n) (toJson .Values.postgresql) (toJson .Values.valkey) (toJson .Values.image) | sha256sum }}
{{- end }}
