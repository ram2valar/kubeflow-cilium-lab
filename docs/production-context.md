# Production Context: The Topology Mismatch Spectrum

This document describes how the Kubeflow–Cilium scheduling conflict manifests
across different production cluster configurations, and how to diagnose each case.

---

## The Root Cause

Kubeflow's pipeline scheduler is topology-agnostic: it places pods based on resource
availability (CPU, memory, GPU count) without considering which availability zone a
pod will land in. This is a deliberate design — Kubernetes scheduling is generally
location-independent, and Kubeflow inherits that assumption.

Cilium is topology-aware by design: it can enforce strict boundaries between zones via
`CiliumNetworkPolicy`, or influence routing via Topology Aware Routing. It cannot,
however, reschedule a pod that has already been placed.

The gap between these two systems produces a class of problem where the workload
scheduler and the network layer each make individually correct decisions that are
collectively wrong.

---

## Scenario 1: Zone-Based CiliumNetworkPolicy (Hard Block)

**When it occurs**: Clusters where operators have applied explicit zone-boundary
network policies — multi-tenant GPU clusters, compliance environments, cost-control
configurations, or dedicated compute pool isolation. See
`manifests/cilium/topology-network-policy.yaml` for a representative configuration.

**Symptom**: GPU workers fail to establish TCP connections to the coordinator.
Training never starts. Pod logs show repeated connection failures with no clear
Kubernetes-level error.

```
[gpu-worker] *** CANNOT REACH COORDINATOR (attempt 12/24) — GPU IDLE ***
```

**Prometheus signals**:
```promql
# Coordinator and workers in different zones (the topology-agnostic signal)
gpu_demo_zones_occupied   # expect 2 during conflict, 1 after fix

# Coordinator in wrong zone (pod-label-based)
gpu_demo_coordinator_zone   # 1 = conflict, 0 = resolved

# Workers failing to connect
gpu_demo_workers_failed
gpu_demo_conflict_score     # 1.0 = full conflict, 0.0 = resolved
```

**kubectl diagnosis**:
```bash
# Map each pod to its actual topology zone
for pod in $(kubectl get pods -n <namespace> -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod "$pod" -n <namespace> -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "pending")
  ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "unknown")
  ROLE=$(kubectl get pod "$pod" -n <namespace> -o jsonpath='{.metadata.labels.role}' 2>/dev/null || echo "unknown")
  echo "$pod → node: $NODE → zone: $ZONE (role: $ROLE)"
done

# Check pod logs for connection errors
kubectl logs <worker-pod> -n <namespace> --tail=30
```

**Cilium-specific diagnosis** (if Hubble is available):
```bash
# Stream dropped flows in real time
kubectl -n kube-system exec ds/cilium -- \
  cilium-dbg monitor --type drop

# Or via Hubble CLI if relay is running
hubble observe --namespace <namespace> --verdict DROPPED
```

**Time to detect**: Seconds to minutes — connection errors appear immediately in
pod logs and the `GPUWorkersCantReachCoordinator` alert fires within 30 seconds.

---

## Scenario 2: Cross-Zone NCCL Latency (Soft Degradation)

**When it occurs**: Any cluster where GPU nodes are concentrated in one availability
zone and the coordinator is scheduled in another, without a hard network policy block.
This is the common case in cloud-managed Kubernetes (EKS, AKS, GKE) where GPU
instances are available in a subset of zones due to hardware availability constraints.

**Symptom**: Training runs, but throughput is significantly below expected. NCCL
AllReduce operations — which require all-to-all gradient synchronisation across all
workers — add 1–5 ms of additional round-trip time per collective operation for
cross-zone traffic. At scale with synchronous data-parallel training, this compounds
into 30–60% GPU utilisation loss. No error is produced. The problem resembles a slow
model, poor data pipeline, or inadequate batch size.

**Prometheus signals**:
```promql
# Cross-zone placement (the key signal — works without any Cilium zone policy)
gpu_demo_zones_occupied   # > 1 means coordinator and workers are split

# With real GPU workloads: look for throughput (samples/sec or tokens/sec)
# significantly below single-zone baseline at equivalent batch size
```

**kubectl diagnosis**:
```bash
# Confirm pods are split across zones
kubectl get pods -n <namespace> -o wide

# Count pods per zone
kubectl get pods -n <namespace> -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  xargs -I{} kubectl get node {} \
    -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' | \
  sort | uniq -c
```

**NCCL-level diagnosis** (with `nccl-tests` on a real GPU cluster):
```bash
# Run all_reduce_perf in the same-zone config and cross-zone config
# Compare bus bandwidth — cross-zone will show lower bandwidth
mpirun -np <num-gpus> all_reduce_perf -b 1G -e 4G -f 2
```

**Time to detect**: Hours to days — throughput degradation is gradual and mixes with
other training variables (learning rate, batch size, model architecture). Requires
deliberate comparison against a same-zone baseline.

---

## Scenario 3: Cross-AZ Egress Cost (Financial Impact)

**When it occurs**: Long-running training jobs with large model parameters or frequent
gradient exchanges that cross AZ boundaries. Most significant at scale (> 50 nodes, or
large models with high gradient volume).

**Symptom**: Cloud billing shows unexpected inter-AZ data transfer charges. No
Kubernetes metric captures this — it appears only in cloud cost management dashboards.
At small scale (< 10 nodes), the cost is negligible; at 500-node scale with large
models, it can be significant.

**Cloud billing signals**:
- **AWS**: Cost Explorer → filter by `DataTransfer-Regional-Bytes` or
  `EC2-DataTransfer-Regional-Bytes-In/Out`
- **Azure**: Azure Cost Management → filter by inter-zone data transfer SKU
- **GCP**: Billing export to BigQuery → filter by `network.googleapis.com` SKU with
  inter-zone description

**Time to detect**: Days — shows up in next billing cycle or real-time cost dashboards.

---

## The Fix Applies to All Three Scenarios

```yaml
# Add to coordinator Deployment spec:
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: [zone-a]   # same zone as GPU nodes

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ml-training         # coordinator + workers share a zone
```

This ensures the coordinator schedules in the same zone as GPU workers regardless of
whether the consequence of cross-zone placement is:
- A hard connectivity block (Scenario 1)
- NCCL AllReduce latency degradation (Scenario 2)
- Cross-AZ egress cost (Scenario 3)

---

## General Diagnostic Runbook

```bash
# 1. Find where all training pods landed
kubectl get pods -n <namespace> -o wide --show-labels

# 2. Map pods to topology zones
for pod in $(kubectl get pods -n <namespace> -o jsonpath='{.items[*].metadata.name}'); do
  NODE=$(kubectl get pod "$pod" -n <namespace> -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "pending")
  ZONE=$(kubectl get node "$NODE" \
    -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "unknown")
  ROLE=$(kubectl get pod "$pod" -n <namespace> -o jsonpath='{.metadata.labels.role}' 2>/dev/null || echo "unknown")
  echo "$pod → node: $NODE → zone: $ZONE (role: $ROLE)"
done

# 3. Check for Pending pods (scheduling failures)
kubectl get pods -n <namespace> | grep -v Running | grep -v Completed

# 4. Describe any Pending pod for scheduler reason
kubectl describe pod <pending-pod> -n <namespace> | grep -A10 Events

# 5. Check Cilium policy enforcement (hard-block case, requires Hubble or cilium-dbg)
# kubectl -n kube-system exec ds/cilium -- cilium-dbg monitor --type drop

# 6. Verify topology spread constraints are correctly configured
kubectl get deployment <coordinator-deployment> -n <namespace> \
  -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' | jq .
kubectl get deployment <coordinator-deployment> -n <namespace> \
  -o jsonpath='{.spec.template.spec.affinity}' | jq .
```

---

## References

- [Kubernetes Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Cilium Network Policy](https://docs.cilium.io/en/stable/security/policy/)
- [Cilium Topology Aware Routing](https://docs.cilium.io/en/stable/network/kubernetes/topology-aware-hints/)
- [GPU Scheduling in Kubernetes](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- [NCCL AllReduce Operations](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/operations.html)
- [Kubernetes SIG-Scheduling](https://github.com/kubernetes/community/tree/master/sig-scheduling)
