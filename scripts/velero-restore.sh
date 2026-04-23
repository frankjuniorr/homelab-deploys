#!/bin/bash
# velero-restore.sh - Restore latest Velero backup to cluster
# Usage: ./scripts/velero-restore.sh [backup-name]
#   backup-name: optional; if omitted, uses the most recent completed backup

set -euo pipefail

VELERO_NS="velero"
RESTORE_NAME="manual-restore-$(date +%Y%m%d-%H%M%S)"

if [ -n "${1:-}" ]; then
  BACKUP_NAME="$1"
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
  restorePVs: true
EOF

echo "Waiting for restore to complete (timeout: 30m)..."
kubectl wait "restore.velero.io/$RESTORE_NAME" \
  -n "$VELERO_NS" \
  --for=jsonpath='{.status.phase}'=Completed \
  --timeout=30m

echo ""
echo "Restore completed: $RESTORE_NAME"
kubectl get "restore.velero.io/$RESTORE_NAME" -n "$VELERO_NS" \
  -o jsonpath='{.status}' | jq .
