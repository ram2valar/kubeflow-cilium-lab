#!/usr/bin/env bash
# =============================================================================
# DEMO PART 1: Reproduce the Scheduling Conflict (BEFORE state)
# =============================================================================
# Run this on stage to show the problem.
# Narration cues are in [brackets].
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
step() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n"; }

# Pin kubeconfig + context so the demo works regardless of the shell's KUBECONFIG
export KUBECONFIG="${HOME}/.kube/config"
kubectl config use-context kind-kubeflow-cilium-demo >/dev/null 2>&1

# ---------------------------------------------------------
step "0. Clean up any previous run"
# ---------------------------------------------------------
kubectl delete job ml-gpu-workers-before -n ml-demo --ignore-not-found
kubectl delete deployment ml-coordinator -n ml-demo --ignore-not-found
kubectl delete service ml-coordinator -n ml-demo --ignore-not-found
kubectl delete namespace ml-demo --ignore-not-found
sleep 5

kubectl create namespace ml-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace ml-demo app=ml-demo --overwrite

# Re-apply Cilium network policies (deleted when namespace was deleted)
kubectl apply -f "${LAB_DIR}/manifests/cilium/topology-network-policy.yaml"
echo "Waiting 10s for Cilium policies to take effect..."
sleep 10

# ---------------------------------------------------------
step "1. Show cluster topology — GPUs only in zone-a"
# [Say: 'Here is our cluster. Two zones. GPU nodes exist only in zone-a.
#        Kubeflow has no knowledge of this topology when it schedules pods.']
# ---------------------------------------------------------
echo ""
kubectl get nodes \
  -L topology.kubernetes.io/zone \
  -L gpu \
  -o custom-columns='NODE:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,GPU-ENABLED:.metadata.labels.gpu,GPU-COUNT:.status.capacity.nvidia\.com/gpu'

echo ""
echo -e "${YELLOW}GPU nodes are ALL in zone-a. The coordinator has no affinity — it can land anywhere.${NC}"

# ---------------------------------------------------------
step "2. Deploy the conflicting workload (no topology constraints)"
# [Say: 'Let me deploy a distributed training job — the way Kubeflow does it
#        by default, with no awareness of network topology.
#        Coordinator: no affinity. Workers: pinned to GPU nodes in zone-a.']
# ---------------------------------------------------------
kubectl apply -f "${LAB_DIR}/manifests/before/gpu-workload-before.yaml"

echo ""
echo "Waiting 40 seconds for pods to schedule and Cilium to enforce..."
sleep 40

# ---------------------------------------------------------
step "3. Show where pods landed — the conflict"
# [Say: 'Look where the coordinator ended up. Zone-b.
#        The GPU workers are in zone-a. Different network zones.
#        The scheduler made a perfectly reasonable decision — zone-b has
#        capacity. It just did not know about the network topology boundary.']
# ---------------------------------------------------------
echo ""
echo -e "${BOLD}Pod placement:${NC}"
kubectl get pods -n ml-demo \
  -o custom-columns='POD:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,ROLE:.metadata.labels.role' \
  --sort-by='.metadata.labels.role'

echo ""
echo -e "${BOLD}Zone for each pod:${NC}"
for pod in $(kubectl get pods -n ml-demo -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod "$pod" -n ml-demo -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "pending")
  ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "unknown")
  ROLE=$(kubectl get pod "$pod" -n ml-demo -o jsonpath='{.metadata.labels.role}' 2>/dev/null || echo "unknown")
  echo "  $pod  →  node: $NODE  →  zone: $ZONE  (role: $ROLE)"
done

# ---------------------------------------------------------
step "4. Show GPU workers failing to reach coordinator"
# [Say: 'Watch the worker logs. They have GPU resources — but they
#        cannot connect to the coordinator. Cilium is enforcing the zone
#        boundary. The GPUs are ALLOCATED but IDLE.']
# ---------------------------------------------------------
echo ""
echo -e "${YELLOW}GPU Worker logs (showing connection failures):${NC}"
WORKER_POD=$(kubectl get pods -n ml-demo -l role=gpu-worker \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$WORKER_POD" ]; then
  kubectl logs "$WORKER_POD" -n ml-demo --tail=20 2>/dev/null || \
    echo "(pod still initialising — wait 10s and check Grafana)"
fi

# ---------------------------------------------------------
step "5. Show Prometheus metrics — low GPU utilisation"
# [Say: 'Here it is in Prometheus. gpu_demo_utilization_pct: 40%.
#        Resources allocated. Nothing computing.
#
#        Now look at gpu_demo_zones_occupied — it returns 2.
#        Coordinator and workers occupy different topology zones.
#        This is the topology-agnostic signal: it works whether the cluster
#        has a hard Cilium zone policy OR just cross-zone latency degradation.
#        In this lab we have the hard block. In many production clusters the
#        same cross-zone placement causes 30–60% NCCL AllReduce throughput
#        loss with no connectivity error at all. Same root cause. Same fix.']
# ---------------------------------------------------------
echo ""
echo -e "${BOLD}Key PromQL queries to run in Prometheus UI (http://localhost:9090):${NC}"
echo ""
echo -e "${BLUE}# GPU utilisation (expect ~40%):${NC}"
echo "  gpu_demo_utilization_pct"
echo ""
echo -e "${BLUE}# Distinct zones occupied by ml-demo pods (expect 2 — the cross-zone signal):${NC}"
echo "  gpu_demo_zones_occupied"
echo ""
echo -e "${BLUE}# Is coordinator in the wrong zone? (expect 1):${NC}"
echo "  gpu_demo_coordinator_zone"
echo ""
echo -e "${BLUE}# Workers stuck in Pending or failed?${NC}"
echo "  gpu_demo_pending_workers"
echo ""
echo -e "${BLUE}# Pods by phase:${NC}"
echo "  count by(phase) (kube_pod_status_phase{namespace=\"ml-demo\"})"
echo ""

# ---------------------------------------------------------
step "6. Show the active Cilium alert"
# [Say: 'Prometheus has fired GPUWorkersCantReachCoordinator.
#        This is the smoking gun for the hard-block case.
#        In production clusters without a zone-based Cilium policy,
#        there is no connectivity alert — only the gpu_demo_zones_occupied
#        metric and degraded throughput signal the problem.
#        The topology spread fix resolves both.']
# ---------------------------------------------------------
echo -e "${RED}Active alert expected: GPUWorkersCantReachCoordinator${NC}"
echo "  Check: http://localhost:9090/alerts"
echo ""
echo -e "${BOLD}Summary of the problem:${NC}"
echo "  ✗ Coordinator: zone-b (fell to CPU nodes — no GPU taint toleration)"
echo "  ✗ GPU Workers: zone-a (pinned to GPU nodes — Cilium blocks cross-zone traffic)"
echo "  ✗ Cilium deny-cross-zone-gpu-traffic policy blocks the connection"
echo "  ✗ gpu_demo_zones_occupied = 2 (topology mismatch confirmed)"
echo "  ✗ GPU utilisation: ~40% — allocated but not computing"
echo ""
echo -e "${YELLOW}━━━ Ready for demo-after.sh to show the fix ━━━${NC}"
