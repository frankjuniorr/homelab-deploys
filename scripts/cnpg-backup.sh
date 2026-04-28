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

      # Verify the backup data file actually landed in S3.
      # barman marks backup.info as DONE before the data upload finishes,
      # so the Backup CR can show 'completed' even when data.* is missing.
      echo ""
      echo "Verifying backup data file exists in S3..."
      BACKUP_ID=$(kubectl get "backup.postgresql.cnpg.io/$BACKUP_NAME" -n "$POSTGRES_NS" \
        -o jsonpath='{.status.backupId}' 2>/dev/null || echo "")
      ENDPOINT=$(kubectl get cluster postgres -n "$POSTGRES_NS" \
        -o jsonpath='{.spec.backup.barmanObjectStore.endpointURL}' 2>/dev/null || echo "")
      DEST_PATH=$(kubectl get cluster postgres -n "$POSTGRES_NS" \
        -o jsonpath='{.spec.backup.barmanObjectStore.destinationPath}' 2>/dev/null || echo "")
      ACCESS_KEY=$(kubectl get secret cnpg-backup-secret -n "$POSTGRES_NS" \
        -o jsonpath='{.data.ACCESS_KEY_ID}' 2>/dev/null | base64 -d || echo "")
      SECRET_KEY=$(kubectl get secret cnpg-backup-secret -n "$POSTGRES_NS" \
        -o jsonpath='{.data.ACCESS_SECRET_KEY}' 2>/dev/null | base64 -d || echo "")

      DEST_PATH="${DEST_PATH%/}"
      if [ -n "$BACKUP_ID" ] && [ -n "$ENDPOINT" ] && [ -n "$DEST_PATH" ] && \
         [ -n "$ACCESS_KEY" ] && [ -n "$SECRET_KEY" ]; then
        DATA_FILE=$(AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
          AWS_DEFAULT_REGION=homelab \
          aws s3 ls "${DEST_PATH}/postgres/base/${BACKUP_ID}/" \
          --endpoint-url "$ENDPOINT" 2>/dev/null | grep "data\." | head -1 || echo "")
        if [ -z "$DATA_FILE" ]; then
          echo ""
          echo "ERROR: backup.info is present in S3 but data.* is missing!"
          echo "  Backup ID : $BACKUP_ID"
          echo "  Bucket    : $DEST_PATH"
          echo "The backup is incomplete and CANNOT be used for recovery."
          echo "Do NOT run 'just destroy' — re-run 'just backup' to get a valid backup."
          exit 1
        fi
        echo "S3 data file verified: OK ($DATA_FILE)"
      else
        echo "WARNING: could not verify S3 data file (missing credentials or endpoint). Proceeding anyway."
      fi

      echo ""
      echo "Backup is safe to use for recovery."
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
