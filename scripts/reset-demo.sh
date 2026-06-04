#!/usr/bin/env bash
# =============================================================================
# Reset ml-demo to clean state between rehearsal runs.
#
# Does NOT touch Cilium, monitoring, or the kind cluster itself.
# Run this after demo-after.sh to prepare for the next demo-before.sh run.
#
# Safe to run any number of times.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[reset]${NC} $*"; }
success() { echo -e "${GREEN}[done]${NC}  $*"; }

export KUBECONFIG="${HOME}/.kube/config"
kubectl config use-context kind-kubeflow-cilium-demo >/dev/null 2>&1

echo ""
echo -e "${BOLD}Resetting ml-demo namespace...${NC}"

# Step 1: Delete all workloads
info "Removing workloads..."
kubectl delete job ml-gpu-workers-before ml-gpu-workers-after \
  -n ml-demo --ignore-not-found 2>/dev/null || true
kubectl delete deployment ml-coordinator -n ml-demo --ignore-not-found 2>/dev/null || true
kubectl delete service ml-coordinator   -n ml-demo --ignore-not-found 2>/dev/null || true

# Step 2: Wait for pods to fully terminate (prevents stale pods in next run's zone output)
info "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=ml-training \
  -n ml-demo --timeout=30s 2>/dev/null || true

# Step 3: Delete and recreate the namespace for a fully clean slate
info "Recreating namespace..."
kubectl delete namespace ml-demo --ignore-not-found 2>/dev/null || true
sleep 3
kubectl create namespace ml-demo
kubectl label namespace ml-demo app=ml-demo

# Step 4: Re-apply Cilium network policies (deleted with the namespace)
info "Re-applying Cilium network policies..."
kubectl apply -f "${LAB_DIR}/manifests/cilium/topology-network-policy.yaml"
echo "  Waiting 5s for Cilium to acknowledge policies..."
sleep 5
kubectl get ciliumnetworkpolicies -n ml-demo \
  -o custom-columns='POLICY:.metadata.name' --no-headers | \
  while read p; do echo "  ✓ $p"; done

echo ""
success "ml-demo is clean and ready."
echo ""
echo -e "${BOLD}Prometheus baseline (should all be 0 or no data):${NC}"
sleep 5
for m in gpu_demo_utilization_pct gpu_demo_zones_occupied gpu_demo_coordinator_zone gpu_demo_conflict_score; do
  val=$(curl -s "http://localhost:9090/api/v1/query?query=${m}" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); r=d['data']['result']; print(r[0]['value'][1] if r else '0 (no data)')" 2>/dev/null || echo "?")
  echo "  ${m} = ${val}"
done
echo ""
echo "Next step: bash scripts/demo-before.sh"
