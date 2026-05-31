# n8n-chart

Helm chart for a scalable [n8n.io](https://n8n.io) deployment on Kubernetes,
with PostgreSQL and Valkey (Redis-compatible).

Based on n8n's [queue-mode scaling guide](https://docs.n8n.io/hosting/scaling/queue-mode/).

## Install

The chart is published to an OCI registry, so no `helm repo add` is needed:

```bash
helm install n8n oci://ghcr.io/a5r0n/charts/n8n --version 0.4.11 -f my-values.yaml
```

A minimal `my-values.yaml`:

```yaml
n8n:
  # Generate once and keep it forever (e.g. `openssl rand -hex 16`).
  encryptionKey: "d9d8f70c3165f6393b7df462b09f73e2"
  webhookUrl: https://n8n.example.com/
  auth:
    enabled: true
    username: "n8n"
    password: "change-me"

ingress:
  enabled: true
  host: n8n.example.com
  className: nginx
```

## Architecture

Two execution topologies are supported via `n8n.executionMode`:

| Mode | Deployments | Datastores |
|------|-------------|------------|
| `queue` (default) | `main` + `webhook` + `worker` | PostgreSQL **and** Valkey |
| `regular` | `main` only | PostgreSQL |

In `queue` mode the main process hands executions to workers through a Valkey
(BullMQ) queue, and a dedicated webhook deployment serves `/webhook/`. In
`regular` mode a single n8n process does everything — good for small/hobby
installs — and Valkey is not required.

## Data stores

Both PostgreSQL and Valkey can either be **bundled** (deployed as subcharts) or
**external** (managed/existing instances). External is recommended for
production.

### PostgreSQL

Bundled (default) — CloudPirates `postgres` subchart:

```yaml
postgresql:
  enabled: true
  auth:
    username: n8n
    database: n8n
    # Prefer existingSecret (key: postgres-password) over an inline password.
    existingSecret: ""
    password: "n8n"
```

External:

```yaml
postgresql:
  enabled: false
  external:
    host: my-postgres.example.com
    port: 5432
    database: n8n
    username: n8n
    existingSecret: my-pg-secret           # holds the password
    existingSecretPasswordKey: postgres-password
```

### Valkey / Redis (queue mode only)

Bundled (default) — valkey-io `valkey` subchart:

```yaml
valkey:
  enabled: true
  auth:
    enabled: false
```

External:

```yaml
valkey:
  enabled: false
  external:
    host: my-valkey.example.com
    port: 6379
    database: "0"
    existingSecret: my-valkey-secret       # optional; omit for no-auth
    existingSecretPasswordKey: redis-password
```

## Secrets

The encryption key and basic-auth password are stored in a Kubernetes **Secret**
(never the ConfigMap). Provide the key in one of two ways:

```yaml
# A) chart-managed: the chart creates the Secret
n8n:
  encryptionKey: "d9d8f70c3165f6393b7df462b09f73e2"

# B) bring your own Secret
n8n:
  existingSecret: my-n8n-secret
  existingSecretKey: encryption-key
```

> ⚠️ The encryption key protects every stored credential. Keep it stable across
> upgrades — if you lose it, saved credentials become unrecoverable.

## Upgrading to 0.5.0

0.5.0 contains intentional breaking changes. Read this before upgrading.

### 0. Delete existing Deployments before upgrading (required for all users)

The Deployment `spec.selector.matchLabels` now includes
`app.kubernetes.io/component` to disambiguate the main/worker/webhook pods.
Because `spec.selector` is **immutable**, `helm upgrade` will fail if the old
Deployments still exist. Delete them first — Helm recreates them:

```bash
NS=<your-namespace>
REL=<your-release>
kubectl delete deployment ${REL}-main ${REL}-worker ${REL}-webhook \
  -n $NS --ignore-not-found
```

(The Service, ConfigMap, Secret, and PVC are unaffected.)

### 1. Encryption key & basic-auth password moved to a Secret
No action needed if you already set `n8n.encryptionKey`. The value is unchanged;
it simply now lands in a Secret instead of the ConfigMap. **Do not regenerate
the key.**

### 2. `redis:` was renamed to `valkey:`
Move any `redis.*` settings under `valkey.*` (and `valkey.external.*` for an
external instance). The chart errors clearly if it still sees `redis.*`. Bundled
queue data is ephemeral, so the Redis→Valkey switch is a brief disruption only.

If you are switching to `n8n.executionMode: regular`, also set
`valkey.enabled: false` — otherwise the bundled Valkey subchart is deployed
even though regular mode does not use it.

### 3. Bundled PostgreSQL changed from Bitnami to CloudPirates
The Bitnami public catalog was deleted (2025-09-29), so the bundled DB moved to
the OSS CloudPirates `postgres` chart. **The chart will refuse to upgrade if it
detects an existing Bitnami Secret — read below before running `helm upgrade`.**

Pick one of three paths:

#### Option A — Zero-migration (recommended)

Keep the old Bitnami StatefulSet running and point n8n at it via external mode.
No data movement, no downtime.

**Before running `helm upgrade`**, annotate the old Bitnami resources so Helm
does not prune them when `postgresql.enabled` flips to `false`:

```bash
NS=<your-namespace>
REL=<your-release>
for kind in statefulset service secret; do
  kubectl annotate $kind ${REL}-postgresql \
    helm.sh/resource-policy=keep -n $NS
done
```

Then upgrade:

```yaml
postgresql:
  enabled: false
  external:
    host: <release>-postgresql          # your existing Bitnami Service name
    database: n8n
    username: n8n
    existingSecret: <release>-postgresql
    existingSecretPasswordKey: password  # Bitnami's custom-user key
```

Copy-paste starter: [`examples/migrate-from-bitnami-external.yaml`](./examples/migrate-from-bitnami-external.yaml)

#### Option B — In-place PVC adoption

The CloudPirates chart uses the same PVC name as Bitnami
(`data-<release>-postgresql-0`). Setting `postgresql.bitnami.migrate: true`
triggers a fully-automated pre-upgrade Job that handles everything:

1. Deletes the old n8n Deployments (selector labels changed — immutable field)
2. Annotates the Bitnami Secret with `helm.sh/resource-policy=keep` so Helm
   doesn't prune it when `existingSecret` is set
3. Deletes the Bitnami StatefulSet and waits for the pod to terminate
4. Copies the data from Bitnami's layout (`data/`) to CloudPirates' layout
   (`pgdata/` for PG < 18, `<major>/docker/` for PG ≥ 18)
5. Fixes ownership to UID 999 (the postgres process user)

Just set these values and run `helm upgrade` — no manual kubectl steps required:

```yaml
postgresql:
  enabled: true
  image:
    tag: "15"                              # REQUIRED: pin to your current PG major
  auth:
    existingSecret: "<release>-postgresql" # the old Bitnami Secret
    secretKeys:
      adminPasswordKey: "password"         # Bitnami's key name
  bitnami:
    migrate: true                          # triggers the automated migration Job
```

> **Check your current PG major** before setting `image.tag`:
> `kubectl exec <release>-postgresql-0 -n <namespace> -- postgres --version`
> CloudPirates defaults to PG 18. Mounting PG 15/16/17 data against PG 18 will
> crash. The hook auto-detects the correct destination path from the data itself.

> **After the upgrade succeeds**, remove `bitnami.migrate: true` (or set it to
> `false`). The Job is idempotent — safe to retry if the upgrade fails mid-way.

Copy-paste starter: [`examples/migrate-from-bitnami-inplace.yaml`](./examples/migrate-from-bitnami-inplace.yaml)

#### Option C — Dump and restore

`pg_dump` from the old DB, provision a fresh instance (bundled or external),
restore, then upgrade.

> The bundled CloudPirates chart defaults to PostgreSQL 18. To pin a specific
> major, set `postgresql.image.tag`. Changing the major on an existing data
> volume requires a dump/restore.

## Values reference

See [`n8n/values.yaml`](./n8n/values.yaml) for the full, documented value
surface. Subchart values are documented upstream
([CloudPirates postgres](https://github.com/CloudPirates-io/helm-charts),
[valkey-io valkey](https://github.com/valkey-io/valkey-helm)).

## Releases & CI

- `lint-test.yml` runs `helm unittest` plus `chart-testing` (lint + install on
  kind) for the bundled, external and single-process modes.
- `ci-version-bump.yml` bumps the chart version on merge to `main`
  (minor when templates change, otherwise patch) and creates the release.
- `push-chart.yml` packages and pushes the chart to the OCI registry.
