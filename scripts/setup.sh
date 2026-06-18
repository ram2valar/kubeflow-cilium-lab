#!/usr/bin/env bash
# =============================================================================
# Phase 1 Setup: Kubeflow + Cilium GPU Scheduling Demo Lab
# KubeCon India 2026
# =============================================================================
# Prerequisites: docker, kind, kubectl, helm (all must be in PATH)
# Host kernel >= 5.10 required for Cilium eBPF (Ubuntu 22.04 / Debian 12: fine)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ---------------------------------------------------------
# STEP 1: Create kind cluster
# ---------------------------------------------------------
info "Step 1/6: Creating kind cluster 'kubeflow-cilium-demo'..."

if kind get clusters 2>/dev/null | grep -q "^kubeflow-cilium-demo$"; then
  warn "Cluster already exists — skipping creation."
else
  kind create cluster --config "${LAB_DIR}/kind-cluster.yaml" --wait 120s
  success "Cluster created."
fi

# Merge kind kubeconfig into ~/.kube/config and set current context
# (kind sometimes fails to merge if ~/.kube/config has null contexts)
info "Merging kubeconfig..."
kind get kubeconfig --name kubeflow-cilium-demo > /tmp/kind-kubeconfig.yaml
if [ -f "${HOME}/.kube/config" ]; then
  KUBECONFIG="${HOME}/.kube/config:/tmp/kind-kubeconfig.yaml" \
    kubectl config view --flatten > /tmp/merged-kubeconfig.yaml
  cp /tmp/merged-kubeconfig.yaml "${HOME}/.kube/config"
else
  mkdir -p "${HOME}/.kube"
  cp /tmp/kind-kubeconfig.yaml "${HOME}/.kube/config"
fi
export KUBECONFIG="${HOME}/.kube/config"
kubectl config use-context kind-kubeflow-cilium-demo

kubectl cluster-info --context kind-kubeflow-cilium-demo

# ---------------------------------------------------------
# STEP 2: Label and taint nodes (kind doesn't support labels in config)
# ---------------------------------------------------------
info "Step 2/6: Applying zone labels and GPU taints to nodes..."

export KUBECONFIG="${HOME}/.kube/config"

# Get worker node names in creation order
WORKERS=($(kubectl get nodes --no-headers \
  --selector='!node-role.kubernetes.io/control-plane' \
  -o custom-columns='NAME:.metadata.name' | sort))

if [ "${#WORKERS[@]}" -lt 4 ]; then
  die "Expected 4 worker nodes, found ${#WORKERS[@]}. Check cluster creation."
fi

GPU_NODE_1="${WORKERS[0]}"
GPU_NODE_2="${WORKERS[1]}"
CPU_NODE_1="${WORKERS[2]}"
CPU_NODE_2="${WORKERS[3]}"

info "GPU nodes (zone-a): ${GPU_NODE_1}, ${GPU_NODE_2}"
info "CPU nodes (zone-b): ${CPU_NODE_1}, ${CPU_NODE_2}"

# Zone-A: GPU nodes
for node in "${GPU_NODE_1}" "${GPU_NODE_2}"; do
  kubectl label node "${node}" \
    topology.kubernetes.io/zone=zone-a \
    topology.kubernetes.io/region=region-1 \
    node-type=gpu \
    gpu=true \
    --overwrite
  # Taint GPU nodes so only tolerating pods land here (simulates GPU exclusivity)
  kubectl taint node "${node}" gpu=present:NoSchedule --overwrite 2>/dev/null || true
done

# Zone-B: CPU nodes
for node in "${CPU_NODE_1}" "${CPU_NODE_2}"; do
  kubectl label node "${node}" \
    topology.kubernetes.io/zone=zone-b \
    topology.kubernetes.io/region=region-1 \
    node-type=cpu \
    gpu=false \
    --overwrite
done

success "Node labels and taints applied."
kubectl get nodes -L topology.kubernetes.io/zone,gpu \
  -o custom-columns='NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,GPU:.metadata.labels.gpu'

# ---------------------------------------------------------
# STEP 3: Install Cilium CNI
# ---------------------------------------------------------
info "Step 3/6: Installing Cilium CNI..."

helm repo add cilium https://helm.cilium.io/ --force-update
helm repo update

CILIUM_VERSION="1.15.6"

# Pre-load image into kind nodes to avoid registry pulls during demo
# --platform linux/arm64 ensures correct image on Apple Silicon (arm64)
ARCH=$(uname -m)
PLATFORM="linux/amd64"
[[ "${ARCH}" == "arm64" ]] && PLATFORM="linux/arm64"
info "Detected platform: ${PLATFORM}"
info "Pulling Cilium image for ${PLATFORM}..."
docker pull --platform "${PLATFORM}" "quay.io/cilium/cilium:v${CILIUM_VERSION}"

info "Loading Cilium image into kind nodes (avoids registry pulls)..."
# kind 0.32.0 uses 'ctr images import --all-platforms' internally. On Apple
# Silicon this fails because the amd64 layers are absent from the local Docker
# content store (we pulled only --platform linux/arm64). The load is an
# optimisation only — if it fails, Cilium Helm will pull from quay.io on each
# node at install time (requires internet during setup, not during demo).
if kind load docker-image "quay.io/cilium/cilium:v${CILIUM_VERSION}" \
    --name kubeflow-cilium-demo 2>/dev/null; then
  success "Cilium image pre-loaded into all kind nodes."
else
  warn "Image pre-load skipped (multi-arch manifest issue with kind 0.32.0 on arm64)."
  warn "Cilium will pull quay.io/cilium/cilium:v${CILIUM_VERSION} per-node at Helm install."
  warn "Internet access required during this setup run."
fi

helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set tunnelProtocol=vxlan \
  --set kubeProxyReplacement=false \
  --set hostServices.enabled=false \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true \
  --set hostPort.enabled=true \
  --set bpf.masquerade=false \
  --set topologyAwareHints.enabled=true \
  --set endpointRoutes.enabled=true \
  --wait --timeout=300s

info "Waiting for Cilium pods to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=k8s-app=cilium \
  --namespace=kube-system \
  --timeout=300s

success "Cilium installed and ready."

# ---------------------------------------------------------
# STEP 4: Install Prometheus + Grafana
# ---------------------------------------------------------
info "Step 4/6: Installing kube-prometheus-stack..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "${LAB_DIR}/manifests/monitoring/values-monitoring.yaml" \
  --wait --timeout=300s

success "Prometheus + Grafana installed."
info "  Access via port-forward (kind does not route NodePorts on macOS):"
info "    bash scripts/open-dashboards.sh"
info "    Grafana:    http://localhost:3000  (admin/admin)"
info "    Prometheus: http://localhost:9090"

# ---------------------------------------------------------
# STEP 5: Create ml-demo namespace + Cilium network policies
# ---------------------------------------------------------
info "Step 5/6: Applying Cilium network policies..."

# Namespace must exist BEFORE CiliumNetworkPolicy objects that target it
kubectl create namespace ml-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace ml-demo app=ml-demo --overwrite

kubectl apply -f "${LAB_DIR}/manifests/cilium/topology-network-policy.yaml"
success "Cilium network policies applied."

# ---------------------------------------------------------
# STEP 6: Apply Prometheus recording rules + Grafana dashboard
# ---------------------------------------------------------
info "Step 6/6: Applying custom Prometheus rules and Grafana dashboard..."

kubectl apply -f "${LAB_DIR}/manifests/monitoring/prometheus-rules.yaml"
kubectl apply -f "${LAB_DIR}/manifests/monitoring/grafana-dashboard-configmap.yaml"

success "Monitoring rules and dashboard applied."

# ---------------------------------------------------------
# NOTE: Kubeflow Pipelines (optional)
# ---------------------------------------------------------
warn "Kubeflow Pipelines is NOT installed by default."
warn "It requires ~8 GiB RAM across pods and external network access during install."
warn "The scheduling conflict demo does NOT need KFP to run."
warn "To install KFP separately, run: bash scripts/install-kfp.sh"

# ---------------------------------------------------------
# Summary
# ---------------------------------------------------------
echo ""
echo "============================================================"
echo -e "${GREEN}Phase 1 lab environment is ready!${NC}"
echo "============================================================"
echo ""
kubectl get nodes -L topology.kubernetes.io/zone,gpu \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,GPU:.metadata.labels.gpu'
echo ""
echo "Next steps:"
echo "  1. bash scripts/open-dashboards.sh — port-forward Grafana (3000) + Prometheus (9090)"
echo "  2. bash scripts/demo-before.sh     — reproduce the scheduling conflict"
echo "  3. Open Grafana: http://localhost:3000  (admin/admin)"
echo "  4. bash scripts/demo-after.sh      — apply the fix"
echo ""
