#!/usr/bin/env bash
# =============================================================================
# Optional: Install Kubeflow Pipelines (standalone)
# =============================================================================
# Requires: ~8 GiB RAM free across the kind cluster, internet access.
# NOT required for the scheduling conflict demo — only needed if you want
# to show the KFP UI during the talk.
# =============================================================================

set -euo pipefail

PIPELINE_VERSION="2.2.0"

warn() { echo "[WARN] $*"; }
info() { echo "[INFO] $*"; }

warn "This installs Kubeflow Pipelines which requires ~8 GiB RAM."
warn "Ensure your machine has at least 12 GiB free before proceeding."
read -rp "Continue? [y/N] " choice
[[ "${choice}" =~ ^[Yy]$ ]] || exit 0

info "Installing KFP ${PIPELINE_VERSION} cluster-scoped resources..."
kubectl apply -k \
  "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${PIPELINE_VERSION}" \
  --timeout=120s

kubectl wait --for=condition=established \
  --timeout=60s crd/applications.app.k8s.io 2>/dev/null || true

info "Installing KFP platform-agnostic manifests..."
kubectl apply -k \
  "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-pns?ref=${PIPELINE_VERSION}" \
  --timeout=120s

info "Waiting for KFP pods (this takes 3-5 minutes)..."
kubectl wait --for=condition=ready pod \
  --selector=app=ml-pipeline \
  --namespace=kubeflow \
  --timeout=600s

echo ""
echo "KFP ready. Access the UI:"
echo "  kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80"
echo "  Then open: http://localhost:8080"
