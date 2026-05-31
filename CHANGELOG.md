# Changelog

All notable changes to this chart are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## 0.5.0

### Added
- **External PostgreSQL** support: set `postgresql.enabled: false` and
  `postgresql.external.*` to point n8n at a managed/external database
  (RDS, CloudNativePG, an existing in-cluster DB, ...). The password is read
  from a Secret via `postgresql.external.existingSecret`.
- **External Valkey/Redis** support: set `valkey.enabled: false` and
  `valkey.external.*` (queue mode only).
- **`n8n.executionMode`** (`queue` | `regular`). `regular` runs a single n8n
  process — no worker/webhook Deployments and no Valkey/Redis required.
- **`n8n.existingSecret` / `n8n.existingSecretKey`** to supply the encryption
  key from a pre-created Secret.
- **`worker.replicaCount`** to size the worker pool (falls back to the
  top-level `replicaCount`).
- Bundled subchart conditions (`postgresql.enabled`, `valkey.enabled`) so the
  subcharts are actually skipped in external mode.
- helm-unittest suites and CI coverage for subchart / external / regular modes.

### Changed
- **Bundled PostgreSQL** now uses the CloudPirates `postgres` chart
  (`oci://registry-1.docker.io/cloudpirates`) instead of the deleted Bitnami
  catalog. Aliased to `postgresql`, so `postgresql.auth.{username,database,
  password}` keep working. The Service/Secret name (`<release>-postgresql`) is
  unchanged — existing ingress rules and references do not need updating.

### Breaking
- **Deployment selectors now include `app.kubernetes.io/component`.** The
  `spec.selector.matchLabels` field is immutable, so upgrading in-place will be
  rejected by Kubernetes. Delete the old Deployments before running
  `helm upgrade` — Helm recreates them automatically.
- **`redis:` was renamed to `valkey:`** and the bundled Redis subchart was
  replaced by the official valkey-io `valkey` chart. Any `redis.*` values now
  cause a clear template error. Bundled queue data is ephemeral, so this is a
  brief disruption, not data loss.
- **The encryption key and basic-auth password moved from the ConfigMap into a
  Secret.** Provide `n8n.encryptionKey` (the chart creates the Secret) or
  `n8n.existingSecret`. **Reuse your existing key** — losing it makes stored
  credentials unrecoverable.
- The chart now **fails fast** with an actionable message when required inputs
  are missing (no encryption key; `postgresql.enabled=false` without an
  external host; queue mode without Valkey).

### Migration
See the "Upgrading to 0.5.0" section in the [README](./README.md#upgrading-to-050).
The lowest-risk path for existing bundled-PostgreSQL users is to switch to
external mode pointing at their existing Bitnami Postgres Service (zero data
migration).
