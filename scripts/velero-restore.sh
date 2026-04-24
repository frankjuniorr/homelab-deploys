#!/bin/bash
# velero-restore.sh - Restore latest Velero backup to cluster
# Usage: ./scripts/velero-restore.sh [backup-name]
#   backup-name: optional; if omitted, uses the most recent completed backup

set -euo pipefail

VELERO_NS="velero"
RESTORE_NAME="manual-restore-$(date +%Y%m%d-%H%M%S)"

if [ -n "${1:-}" ]; then
  BACKUP_NAME="$1"
  BACKUP_PHASE=$(kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$BACKUP_PHASE" != "Completed" ]; then
    echo "Backup '$BACKUP_NAME' not found or not Completed (phase: ${BACKUP_PHASE:-not found})."
    exit 1
  fi
else
  echo "Fetching latest completed Velero backup..."
  BACKUP_NAME=$(kubectl get backup.velero.io -n "$VELERO_NS" -o json \
    | jq -r '[.items[] | select(.status.phase == "Completed")] | sort_by(.metadata.creationTimestamp) | last | .metadata.name')

  if [ -z "$BACKUP_NAME" ] || [ "$BACKUP_NAME" = "null" ]; then
    echo "No completed Velero backups found. Nothing to restore."
    exit 0
  fi
fi

echo "Backup to restore: $BACKUP_NAME"
echo "Restore name:      $RESTORE_NAME"
echo ""

kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: $RESTORE_NAME
  namespace: $VELERO_NS
spec:
  backupName: $BACKUP_NAME
  includedNamespaces:
    - "*"
  excludedNamespaces:
    - velero
  restorePVs: true
EOF

echo "Waiting for restore to complete (timeout: 30m)..."
DEADLINE=$((SECONDS + 1800))
while [ $SECONDS -lt $DEADLINE ]; do
  PHASE=$(kubectl get "restore.velero.io/$RESTORE_NAME" -n "$VELERO_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  case "$PHASE" in
    Completed)
      echo ""
      echo "Restore completed: $RESTORE_NAME"
      kubectl get "restore.velero.io/$RESTORE_NAME" -n "$VELERO_NS" \
        -o jsonpath='{.status}' | jq .
      exit 0
      ;;
    PartiallyFailed|Failed)
      echo ""
      echo "Restore ended with status: $PHASE"
      kubectl get "restore.velero.io/$RESTORE_NAME" -n "$VELERO_NS" \
        -o jsonpath='{.status}' | jq .
      exit 1
      ;;
  esac
  echo "  Status: ${PHASE:-Pending}..."
  sleep 15
done

echo "Timeout waiting for restore to complete."
exit 1
