#!/usr/bin/env bash
# =============================================================================
# DEMO PART 2: Apply the Fix (AFTER state)
# =============================================================================
# Run this immediately after demo-before.sh on stage.
# Narration cues are in [brackets].
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
step() { echo -e "\n${BOLD}${GREEN}━━━ $* ━━━${NC}\n"; }

# ---------------------------------------------------------
step "1. Show the fix — topology spread constraints YAML"
# [Say: 'Here's the fix. Three additions to our workload spec.
#        These are Kubernetes-native — no Kubeflow changes, no Cilium changes.']
# ---------------------------------------------------------
echo ""
echo -e "${BOLD}The fix — added to coordinator Deployment:${NC}"
cat << 'YAML'

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                  - zone-a          # ← Pin coordinator to GPU zone

  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: ml-training           # ← All ml-training pods must be in same zone

YAML

echo -e "${BOLD}The same constraint on GPU workers (ensures intra-zone spread):${NC}"
cat << 'YAML'

  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: ml-training
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname   # ← Also spread across nodes within zone-a
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          role: gpu-worker

YAML

# ---------------------------------------------------------
step "2. Tear down the broken workload"
# [Say: 'Let me remove the old workload and apply the fixed version.']
# ---------------------------------------------------------
kubectl delete job ml-gpu-workers-before -n ml-demo --ignore-not-found
kubectl delete job ml-gpu-workers-after -n ml-demo --ignore-not-found
kubectl delete deployment ml-coordinator -n ml-demo --ignore-not-found
kubectl delete service ml-coordinator -n ml-demo --ignore-not-found
sleep 5

# ---------------------------------------------------------
step "3. Apply the fixed workload"
# [Say: 'Applying the fixed manifest now.']
# ---------------------------------------------------------
kubectl apply -f "${LAB_DIR}/manifests/after/gpu-workload-after.yaml"

echo ""
echo "Waiting 25 seconds for pods to schedule and connect..."
sleep 25

# ---------------------------------------------------------
step "4. Show pod placement — all in zone-a now"
# [Say: 'Look at this. Coordinator: zone-a. Workers: zone-a.
#        The scheduler placed everything in the same network zone.
#        Cilium's intra-zone policy allows all of this traffic.']
# ---------------------------------------------------------
echo ""
echo -e "${BOLD}Pod placement after fix:${NC}"
kubectl get pods -n ml-demo \
  -o custom-columns='POD:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,ROLE:.metadata.labels.role' \
  --sort-by='.metadata.labels.role'

echo ""
echo -e "${BOLD}Zone verification:${NC}"
for pod in $(kubectl get pods -n ml-demo -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod "$pod" -n ml-demo -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "pending")
  ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "unknown")
  ROLE=$(kubectl get pod "$pod" -n ml-demo -o jsonpath='{.metadata.labels.role}' 2>/dev/null || echo "unknown")
  if [ "$ZONE" = "zone-a" ]; then
    echo -e "  $pod  →  zone: ${GREEN}$ZONE ✓${NC}  (role: $ROLE)"
  else
    echo -e "  $pod  →  zone: ${RED}$ZONE ✗${NC}  (role: $ROLE)"
  fi
done

# ---------------------------------------------------------
step "5. Show GPU workers successfully connecting"
# [Say: 'And the workers — they're connected. Training is running.
#        GPUs are actually computing.']
# ---------------------------------------------------------
echo ""
echo -e "${YELLOW}GPU Worker logs (showing successful connection):${NC}"
sleep 10
WORKER_POD=$(kubectl get pods -n ml-demo -l role=gpu-worker \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$WORKER_POD" ]; then
  kubectl logs "$WORKER_POD" -n ml-demo --tail=20 2>/dev/null || \
    echo "(pod still initializing — check Grafana in 30s)"
fi

# ---------------------------------------------------------
step "6. Show the improved Prometheus metrics"
# [Say: 'Back to Prometheus. GPU utilization is now 85%.
#        Same cluster, same workload, same GPUs — just topology-aware scheduling.']
# ---------------------------------------------------------
echo ""
echo -e "${BOLD}Key PromQL queries — now showing improved state:${NC}"
echo ""
echo -e "${GREEN}# GPU utilization (expect ~85%):${NC}"
echo "  gpu_demo_utilization_pct"
echo ""
echo -e "${GREEN}# Distinct zones occupied (expect 1 — all pods in zone-a):${NC}"
echo "  gpu_demo_zones_occupied"
echo ""
echo -e "${GREEN}# Coordinator in wrong zone? (expect 0):${NC}"
echo "  gpu_demo_coordinator_zone"
echo ""
echo -e "${GREEN}# Any pending workers? (expect 0):${NC}"
echo "  gpu_demo_pending_workers"
echo ""
echo -e "${GREEN}# Conflict score (expect 0.0):${NC}"
echo "  gpu_demo_conflict_score"
echo ""

# ---------------------------------------------------------
step "7. Before/After summary for the slide"
# ---------------------------------------------------------
echo -e "${BOLD}Before vs After:${NC}"
printf "%-35s %-15s %-15s\n" "Metric" "Before (broken)" "After (fixed)"
printf "%-35s %-15s %-15s\n" "─────────────────────────────────" "───────────────" "───────────────"
printf "%-35s %-15s %-15s\n" "GPU utilization"         "~40%"           "~85%"
printf "%-35s %-15s %-15s\n" "Zones occupied"          "2 ✗"            "1 ✓"
printf "%-35s %-15s %-15s\n" "Coordinator zone"        "zone-b ✗"       "zone-a ✓"
printf "%-35s %-15s %-15s\n" "Cross-zone Cilium blocks" "Active ✗"       "None ✓"
printf "%-35s %-15s %-15s\n" "Training progress"       "Stalled ✗"      "Running ✓"
printf "%-35s %-15s %-15s\n" "Fix required"            "—"             "3 YAML additions"
echo ""
echo -e "${GREEN}Demo complete. Refer to GitHub repo for all manifests.${NC}"
