# n8n-chart

Helm Chart for scalable n8n.io
with redis & postgres.

https://docs.n8n.io/getting-started/installation/advanced/scaling-n8n.html

## install

we use the new OCI registery,
so install is simple:

```bash
export HELM_EXPERIMENTAL_OCI=1
helm install n8n oci://ghcr.io/a5r0n/charts/n8n --version 0.2.15
```

example values:

```yaml
#set replicaCount for n8n workers
replicaCount: 5

n8n:
  encryptionKey: d9d8f70c3165f6393b7df462b09f73e2
  webhookUrl: https://n8n.local/
  auth:
    enabled: true
    username: "n8n"
    password: "N8nPassW0r$"

postgresql:
  enabled: true
  auth:
    database: "n8n"
    username: "n8n"
    password: "N8nPassW0r$"
  persistence:
    size: 1Gi

ingress:
  enabled: true
  host: n8n.local
  className: nginx
```

see [values.yaml](./n8n/values.yaml)

## CI Version Bump Workflow

A new workflow has been added to automate chart version bump and release. The workflow is defined in the `.github/workflows/ci-version-bump.yml` file and performs the following actions:

* Bumps patch version on n8n major/minor and patch for n8n patch versions.
* Bumps minor version for template changes.
* Only pushes version changes on main branch runs.
* Comments on the next version to publish after a PR merge.

The workflow is triggered on push and pull request events to the `main` branch. It performs the following steps:

1. Checks out the code.
2. Sets up Python environment.
3. Installs `python semver`.
4. Bumps the chart version based on changes.
5. Commits the changes.
6. Creates a release.
7. Comments on the next version to publish after a PR merge.

The version bumping is done for the Helm chart version, not for a Node.js package.
