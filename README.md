# n8n-chart

Helm Chart for scalable n8n.io
with redis & postgres.

https://docs.n8n.io/getting-started/installation/advanced/scaling-n8n.html

## install

we use the new OCI registery,
so install is simple:

```bash
export HELM_EXPERIMENTAL_OCI=1
helm install n8n oci://ghcr.io/a5r0n/charts/n8n --version 0.2.8
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
