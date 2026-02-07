#!/bin/bash
# ============================================================
# ArgoCD CLI Deployment Script for Observer
# ============================================================
# Usage: ./deploy-observer.sh
#
# Prerequisites:
#   - argocd CLI installed and logged in
#   - kubectl access to target cluster
# ============================================================

set -euo pipefail

# Configuration
APP_NAME="observer-prod"
NAMESPACE="observer-prod"
REPO_URL="https://github.com/tawbury/Deployment"
CHART_PATH="infra/helm/observer"
REVISION="HEAD"

echo "============================================================"
echo "ArgoCD Deployment: ${APP_NAME}"
echo "============================================================"
echo "Repository: ${REPO_URL}"
echo "Chart Path: ${CHART_PATH}"
echo "Namespace:  ${NAMESPACE}"
echo "============================================================"

# Step 1: Create or update ArgoCD Application
echo ""
echo "=== Step 1: Creating ArgoCD Application ==="
argocd app create "${APP_NAME}" \
  --repo "${REPO_URL}" \
  --path "${CHART_PATH}" \
  --revision "${REVISION}" \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace "${NAMESPACE}" \
  --values values.yaml \
  --values values-prod.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true \
  --sync-option PrunePropagationPolicy=foreground \
  --upsert

echo "Application created/updated successfully."

# Step 2: Trigger sync
echo ""
echo "=== Step 2: Syncing Application ==="
argocd app sync "${APP_NAME}" --force

# Step 3: Wait for sync completion
echo ""
echo "=== Step 3: Waiting for sync to complete ==="
argocd app wait "${APP_NAME}" --sync --timeout 300

# Step 4: Display status
echo ""
echo "=== Step 4: Application Status ==="
argocd app get "${APP_NAME}"

# Step 5: Show pod status
echo ""
echo "=== Step 5: Pod Status ==="
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=observer

echo ""
echo "============================================================"
echo "Deployment complete!"
echo "============================================================"
echo ""
echo "Verification commands:"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=observer -f"
echo "  kubectl exec -n ${NAMESPACE} -it \$(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/name=observer -o jsonpath='{.items[0].metadata.name}') -- ls -la /opt/platform/runtime/observer/"
echo ""
