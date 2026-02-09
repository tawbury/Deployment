#!/bin/bash
# ============================================================
# QTS ArgoCD Deployment Script
# ============================================================
# Usage: ./deploy-qts.sh [sync|create|delete|status]
# ============================================================
set -euo pipefail

APP_NAME="qts-prod"
NAMESPACE="observer-prod"
REPO_URL="https://github.com/tawbury/Deployment"
CHART_PATH="infra/helm/qts"

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  create  - Create ArgoCD application"
    echo "  sync    - Sync application (default)"
    echo "  delete  - Delete application"
    echo "  status  - Show application status"
    echo "  logs    - Show QTS pod logs"
    exit 1
}

create_app() {
    echo "Creating ArgoCD application: ${APP_NAME}"
    argocd app create "${APP_NAME}" \
        --repo "${REPO_URL}" \
        --path "${CHART_PATH}" \
        --revision HEAD \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace "${NAMESPACE}" \
        --values values.yaml \
        --values values-prod.yaml \
        --sync-policy automated \
        --auto-prune \
        --self-heal \
        --upsert
    echo "Application created successfully"
}

sync_app() {
    echo "Syncing ArgoCD application: ${APP_NAME}"
    argocd app sync "${APP_NAME}"
    argocd app wait "${APP_NAME}" --sync --timeout 300
    echo "Sync completed"
}

delete_app() {
    echo "Deleting ArgoCD application: ${APP_NAME}"
    argocd app delete "${APP_NAME}" --cascade
    echo "Application deleted"
}

status_app() {
    echo "Application status: ${APP_NAME}"
    argocd app get "${APP_NAME}"
}

show_logs() {
    echo "QTS pod logs (last 50 lines):"
    kubectl logs -n "${NAMESPACE}" -l app.kubernetes.io/name=qts --tail=50
}

# Main
COMMAND="${1:-sync}"

case "${COMMAND}" in
    create)
        create_app
        ;;
    sync)
        sync_app
        ;;
    delete)
        delete_app
        ;;
    status)
        status_app
        ;;
    logs)
        show_logs
        ;;
    *)
        usage
        ;;
esac
