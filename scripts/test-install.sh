#!/usr/bin/env bash
# Local integration test — mirrors the CI install job exactly.
# Usage:
#   ./scripts/test-install.sh          # full run
#   ./scripts/test-install.sh --no-create  # skip cluster creation (reuse existing)
#   ./scripts/test-install.sh --no-delete  # keep cluster after run (faster re-runs)
set -euo pipefail

CLUSTER_NAME="n8n-chart-test"
NO_CREATE=false
NO_DELETE=false

for arg in "$@"; do
  case $arg in
    --no-create) NO_CREATE=true ;;
    --no-delete) NO_DELETE=true ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { echo ""; echo "▶ $*"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; exit 1; }

cleanup() {
  if [[ "$NO_DELETE" == false ]]; then
    log "Deleting kind cluster"
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  else
    echo ""
    echo "Cluster preserved: kind delete cluster --name $CLUSTER_NAME"
  fi
}
trap cleanup EXIT

# ── cluster ───────────────────────────────────────────────────────────────────
if [[ "$NO_CREATE" == false ]]; then
  log "Creating kind cluster ($CLUSTER_NAME)"
  kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  # Pin node image: kind v0.31 defaults to v1.35 which fails kubelet init on WSL2
  kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.32.0
fi
export KUBECONFIG=/tmp/kind-n8n-chart-test.kubeconfig
kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG" 2>/dev/null || \
  KUBECONFIG="$HOME/.kube/config"

log "Building chart dependencies"
helm repo add valkey https://valkey.io/valkey-helm/ --force-update >/dev/null
helm dependency build ./n8n >/dev/null

# ── external fixtures ─────────────────────────────────────────────────────────
log "Pre-creating external fixtures"
kubectl create namespace external --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic pg-cred -n external \
  --from-literal=postgres-password=testpw \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic n8n-enc -n external \
  --from-literal=encryption-key=d9d8f70c3165f6393b7df462b09f73e2 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl run pg-fixture -n external --image=postgres:16 \
  --env=POSTGRES_PASSWORD=testpw \
  --env=POSTGRES_USER=n8n \
  --env=POSTGRES_DB=n8n \
  --port=5432 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl expose pod pg-fixture -n external --port=5432 2>/dev/null || true

kubectl run valkey-fixture -n external \
  --image=valkey/valkey:8 --port=6379 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl expose pod valkey-fixture -n external --port=6379 2>/dev/null || true

log "Waiting for fixtures to be Ready"
kubectl wait pod/pg-fixture pod/valkey-fixture \
  --for=condition=Ready -n external --timeout=300s

# ── parallel installs ─────────────────────────────────────────────────────────
log "Installing all scenarios in parallel"
helm install bundled-queue ./n8n \
  -f n8n/ci/default-subchart-values.yaml \
  -n bundled-queue --create-namespace \
  --wait --timeout 5m > /tmp/bq.log 2>&1 &
PID_BQ=$!

helm install single-process ./n8n \
  -f n8n/ci/single-process-values.yaml \
  -n single-process --create-namespace \
  --wait --timeout 5m > /tmp/sp.log 2>&1 &
PID_SP=$!

helm install external ./n8n \
  -f n8n/ci/external-pg-values.yaml \
  -n external \
  --wait --timeout 5m > /tmp/ex.log 2>&1 &
PID_EX=$!

FAILED=0
wait $PID_BQ || { echo "=== bundled-queue failed ==="; cat /tmp/bq.log; FAILED=$((FAILED+1)); }
wait $PID_SP || { echo "=== single-process failed ==="; cat /tmp/sp.log; FAILED=$((FAILED+1)); }
wait $PID_EX || { echo "=== external failed ==="; cat /tmp/ex.log; FAILED=$((FAILED+1)); }
[[ $FAILED -eq 0 ]] || fail "$FAILED install(s) failed"
pass "All installs healthy"

# ── upgrade: guard test ───────────────────────────────────────────────────────
log "Upgrade: Bitnami guard must block blind upgrade"
PG_PASS=$(kubectl get secret bundled-queue-postgresql \
  -n bundled-queue -o jsonpath='{.data.postgres-password}')
kubectl patch secret bundled-queue-postgresql \
  -n bundled-queue --type merge \
  -p "{\"data\":{\"password\":\"${PG_PASS}\"}}"

OUT=$(helm upgrade bundled-queue ./n8n \
  -f n8n/ci/default-subchart-values.yaml \
  -n bundled-queue --dry-run=server 2>&1 || true)
if echo "$OUT" | grep -q "Detected an existing Bitnami"; then
  pass "Guard blocked the blind upgrade"
else
  echo "$OUT"
  fail "Guard did not fire"
fi

# ── upgrade: Option B migration ───────────────────────────────────────────────
log "Upgrade: Option B in-place migration"

# Prevent Helm from deleting the Secret when existingSecret is set (in the
# real migration the Secret is owned by a different release and Helm never
# touches it; here we simulate that with resource-policy=keep).
kubectl annotate secret bundled-queue-postgresql \
  -n bundled-queue "helm.sh/resource-policy=keep"

kubectl delete statefulset bundled-queue-postgresql -n bundled-queue
kubectl wait --for=delete pod/bundled-queue-postgresql-0 \
  -n bundled-queue --timeout=60s || true

helm upgrade bundled-queue ./n8n \
  -f n8n/ci/default-subchart-values.yaml \
  -n bundled-queue \
  --set postgresql.auth.existingSecret=bundled-queue-postgresql \
  --set postgresql.auth.secretKeys.adminPasswordKey=password \
  --wait --timeout 5m
pass "Option B migration succeeded"

# ── smoke test: full Bitnami → CloudPirates migration with data ────────────────
log "Smoke test: Bitnami migration hook (data must survive)"

# Install pinned to PG15 — mirrors a real Bitnami install (Bitnami used PG15/16/17).
# CloudPirates PG<18 stores data at pgdata/ on the PVC.
helm install bitnami-migrate ./n8n \
  -f n8n/ci/default-subchart-values.yaml \
  -n bitnami-migrate --create-namespace \
  --set-string postgresql.image.tag=15 \
  --wait --timeout 5m > /tmp/bm.log 2>&1 || { cat /tmp/bm.log; fail "bitnami-migrate install failed"; }

# Insert a canary row to verify data survives migration
kubectl exec -n bitnami-migrate statefulset/bitnami-migrate-postgresql -- \
  psql -U n8n -d n8n -c \
  "CREATE TABLE _canary (v text); INSERT INTO _canary VALUES ('survived');" >/dev/null

# Add the Bitnami 'password' key fingerprint (triggers the upgrade guard)
PG_PASS_BM=$(kubectl get secret bitnami-migrate-postgresql \
  -n bitnami-migrate -o jsonpath='{.data.postgres-password}')
kubectl patch secret bitnami-migrate-postgresql \
  -n bitnami-migrate --type merge \
  -p "{\"data\":{\"password\":\"${PG_PASS_BM}\"}}"

# Scale down postgres so we can safely manipulate the PVC
kubectl scale statefulset bitnami-migrate-postgresql \
  -n bitnami-migrate --replicas=0
kubectl wait --for=delete pod/bitnami-migrate-postgresql-0 \
  -n bitnami-migrate --timeout=60s || true

# Simulate Bitnami data layout: copy pgdata/ (CloudPirates PG<18 path) → data/
# (Bitnami path), remove pgdata/. The hook will reverse this.
kubectl run pg-sim -n bitnami-migrate --image=busybox --restart=Never \
  --overrides='{
    "spec":{
      "volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"data-bitnami-migrate-postgresql-0"}}],
      "containers":[{"name":"s","image":"busybox",
        "command":["sh","-c","cp -a /d/pgdata/. /d/data/ && rm -rf /d/pgdata && echo done"],
        "volumeMounts":[{"name":"d","mountPath":"/d"}]}]}}' >/dev/null
kubectl wait pod/pg-sim -n bitnami-migrate --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s
kubectl logs pod/pg-sim -n bitnami-migrate
kubectl delete pod/pg-sim -n bitnami-migrate

# Upgrade — hook handles all pre-steps automatically:
#   deletes Deployments, annotates Secret, deletes StatefulSet + waits,
#   then copies data/ → pgdata/ and chowns
helm upgrade bitnami-migrate ./n8n \
  -f n8n/ci/default-subchart-values.yaml \
  -n bitnami-migrate \
  --set-string postgresql.image.tag=15 \
  --set postgresql.auth.existingSecret=bitnami-migrate-postgresql \
  --set postgresql.auth.secretKeys.adminPasswordKey=password \
  --set postgresql.bitnami.migrate=true \
  --wait --timeout 5m > /tmp/bm-upgrade.log 2>&1 \
  || { cat /tmp/bm-upgrade.log; fail "bitnami-migrate upgrade failed"; }

# Verify canary data survived
RESULT=$(kubectl exec -n bitnami-migrate statefulset/bitnami-migrate-postgresql -- \
  psql -U n8n -d n8n -t -c "SELECT v FROM _canary;" 2>&1)
if echo "$RESULT" | grep -q "survived"; then
  pass "Bitnami migration smoke: data survived"
else
  echo "$RESULT"
  fail "Bitnami migration smoke: data lost after migration"
fi

echo ""
echo "All tests passed."
