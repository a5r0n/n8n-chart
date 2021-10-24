# n8n-chart
Helm Chart for n8n.io

## install 
we use the new OCI registery,
so install is simple.

```bash
export HELM_EXPERIMENTAL_OCI=1
helm install n8n oci://ghcr.io/a5r0n/charts/n8n --version 0.1.0
```
example values:
```yaml
n8n:
  auth:
    enabled: true
    username: "n8n"
    password: "N8nPassW0r$"
  
postgresql:
  postgresqlPassword: "N8nPassW0r$"
```

see [values.yaml](./n8n/values.yaml)
