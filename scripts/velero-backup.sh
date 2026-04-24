#!/bin/bash
# velero-backup.sh - Trigger a manual Velero backup
# Usage: ./scripts/velero-backup.sh [backup-name]
#   backup-name: optional; defaults to manual-backup-YYYYMMDD-HHMMSS

set -euo pipefail

VELERO_NS="velero"
BACKUP_NAME="${1:-manual-backup-$(date +%Y%m%d-%H%M%S)}"

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
      exit 0
      ;;
    Failed|PartiallyFailed)
      echo ""
      echo "Backup ended with status: $PHASE"
      kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
        -o jsonpath='{.status}' | jq .
      exit 1
      ;;
  esac
  echo "  Status: ${PHASE:-Pending}..."
  sleep 15
done

echo "Timeout waiting for backup to complete."
exit 1
