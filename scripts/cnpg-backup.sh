#!/bin/bash
# cnpg-backup.sh - Trigger a manual CNPG barman-cloud backup
# Usage: ./scripts/cnpg-backup.sh
#   Backup name auto-generated: manual-backup-YYYYMMDD-HHMMSS

set -euo pipefail

POSTGRES_NS="postgres"
BACKUP_NAME="manual-backup-$(date +%Y%m%d-%H%M%S)"

echo "CNPG backup name: $BACKUP_NAME"
echo ""

kubectl create -n "$POSTGRES_NS" -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: $POSTGRES_NS
spec:
  method: barmanObjectStore
  cluster:
    name: postgres
EOF

echo "Waiting for CNPG backup to complete (timeout: 30m)..."
DEADLINE=$((SECONDS + 1800))
while [ $SECONDS -lt $DEADLINE ]; do
  PHASE=$(kubectl get "backup.postgresql.cnpg.io/$BACKUP_NAME" -n "$POSTGRES_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  case "$PHASE" in
    completed)
      echo ""
      echo "CNPG backup completed: $BACKUP_NAME"
      kubectl get "backup.postgresql.cnpg.io/$BACKUP_NAME" -n "$POSTGRES_NS" \
        -o jsonpath='{.status}' | jq .

      # Force a WAL segment switch so the archiver ships all WAL segments required
      # by this backup before the caller proceeds to destroy the cluster.
      # Without this, the async WAL archiver may not have uploaded begin_wal..end_wal
      # by the time the cluster is torn down, leaving an unrestorable backup in S3.
      echo ""
      echo "Forcing WAL segment switch to flush pending archives..."
      PRIMARY=$(kubectl get cluster postgres -n "$POSTGRES_NS" \
        -o jsonpath='{.status.currentPrimary}' 2>/dev/null || echo "")
      if [ -n "$PRIMARY" ]; then
        kubectl exec -n "$POSTGRES_NS" "$PRIMARY" -- \
          psql -U postgres -c "SELECT pg_switch_wal();" -q 2>/dev/null || true
        echo "Waiting 30s for WAL archiver to ship pending segments..."
        sleep 30
        echo "WAL flush complete."
      fi
      exit 0
      ;;
    failed)
      echo ""
      echo "CNPG backup failed: $BACKUP_NAME"
      kubectl get "backup.postgresql.cnpg.io/$BACKUP_NAME" -n "$POSTGRES_NS" \
        -o jsonpath='{.status}' | jq .
      exit 1
      ;;
  esac
  echo "  Status: ${PHASE:-Pending}..."
  sleep 15
done

echo "Timeout waiting for CNPG backup to complete."
exit 1
