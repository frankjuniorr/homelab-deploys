#!/bin/bash
# velero-backup.sh - Trigger a manual Velero backup
# Usage: ./scripts/velero-backup.sh [backup-name]
#   backup-name: optional; defaults to manual-backup-YYYYMMDD-HHMMSS

set -euo pipefail

VELERO_NS="velero"
BACKUP_NAME="${1:-manual-backup-$(date +%Y%m%d-%H%M%S)}"

echo "Triggering Velero backup: $BACKUP_NAME"
echo ""

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

echo "Waiting for backup to complete (timeout: 30m)..."
kubectl wait "backup.velero.io/$BACKUP_NAME" \
  -n "$VELERO_NS" \
  --for=jsonpath='{.status.phase}'=Completed \
  --timeout=30m

echo ""
echo "Backup completed: $BACKUP_NAME"
kubectl get "backup.velero.io/$BACKUP_NAME" -n "$VELERO_NS" \
  -o jsonpath='{.status}' | jq .
