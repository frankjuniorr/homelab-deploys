#!/bin/bash
# velero-backup.sh - Trigger a manual Velero backup
# Usage: ./scripts/velero-backup.sh [backup-name]
#   backup-name: optional; defaults to manual-backup-YYYYMMDD-HHMMSS

set -euo pipefail

VELERO_NS="velero"
BACKUP_NAME="${1:-manual-backup-$(date +%Y%m%d-%H%M%S)}"
VELERO_BUCKET="homelab-velero"
S3_ENDPOINT="http://192.168.1.52:3900"

echo "Backup name: $BACKUP_NAME"
echo ""

if kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" &>/dev/null; then
  echo "Backup '$BACKUP_NAME' already exists. Monitoring its status..."
else
  kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: $VELERO_NS
spec:
  includedNamespaces:
    - "*"
  storageLocation: default
  ttl: 720h0m0s
EOF
fi

check_backup_logs() {
  local backup_name="$1"
  local tmp_log="/tmp/${backup_name}-logs.gz"

  echo ""
  echo "Checking backup integrity (downloading log from S3)..."

  if ! aws s3 cp \
      "s3://${VELERO_BUCKET}/backups/${backup_name}/${backup_name}-logs.gz" \
      "$tmp_log" --endpoint-url "$S3_ENDPOINT" --quiet 2>/dev/null; then
    echo "  Warning: could not download backup log from S3."
    return 0
  fi

  local errors
  errors=$(zcat "$tmp_log" 2>/dev/null | grep 'level=error' || true)
  rm -f "$tmp_log"

  if [ -z "$errors" ]; then
    echo "  Integrity check passed — no errors found in backup log."
    return 0
  fi

  local error_count
  error_count=$(echo "$errors" | wc -l)
  echo ""
  echo "!! Integrity check FAILED — ${error_count} error(s) in backup log:"
  echo "$errors" | sed 's/^/    /'
  return 1
}

echo "Waiting for backup to complete (timeout: 30m)..."
DEADLINE=$((SECONDS + 1800))
while [ $SECONDS -lt $DEADLINE ]; do
  PHASE=$(kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  case "$PHASE" in
    Completed)
      echo ""
      echo "Backup completed: $BACKUP_NAME"
      kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
        -o jsonpath='{.status}' | jq .
      check_backup_logs "$BACKUP_NAME"
      exit $?
      ;;
    Failed|PartiallyFailed)
      echo ""
      echo "Backup ended with status: $PHASE"
      kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
        -o jsonpath='{.status}' | jq .
      check_backup_logs "$BACKUP_NAME"
      exit 1
      ;;
  esac
  echo "  Status: ${PHASE:-Pending}..."
  sleep 15
done

echo "Timeout waiting for backup to complete."
exit 1
