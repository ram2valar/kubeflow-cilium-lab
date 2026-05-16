# Kubeflow + Cilium GPU Scheduling Demo Lab
**KubeCon India 2026** — "When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes"

---

## What this lab does

Reproduces a scheduling conflict where Kubeflow places GPU worker pods in zone-a
and a coordinator pod in zone-b. Cilium's network policy blocks cross-zone GPU worker
traffic, leaving GPUs allocated but idle (~40% utilization). Applying pod topology
spread constraints resolves the conflict (~85% utilization).

## Prerequisites

- Docker
- `kind`
- `kubectl`
- `helm`

## Quick Start

```bash
# 1. Bring up the full environment (takes ~10 min)
bash scripts/setup.sh

# 2. Run the "before" demo (shows the conflict)
bash scripts/demo-before.sh

# 3. Open Grafana and show the 40% utilization
#    http://localhost:30080  (admin/admin)
#    Dashboard: "GPU Scheduling Demo — Kubeflow + Cilium"

# 4. Run the "after" demo (applies the fix)
bash scripts/demo-after.sh

# 5. Show Grafana again — utilization jumps to 85%
```

## Lab Architecture

```
kind cluster: kubeflow-cilium-demo
├── control-plane
├── worker-zone-a-gpu-1   (zone-a, gpu=true, 2x nvidia.com/gpu fake)
├── worker-zone-a-gpu-2   (zone-a, gpu=true, 2x nvidia.com/gpu fake)
├── worker-zone-b-cpu-1   (zone-b, gpu=false)
└── worker-zone-b-cpu-2   (zone-b, gpu=false)

Installed:
├── Cilium 1.15.x      CNI with topology-aware routing + zone network policies
├── Kubeflow Pipelines  ML workload orchestration
├── Prometheus          Metrics (with custom GPU scheduling rules)
└── Grafana             Dashboard (auto-imported from ConfigMap)
```

## The Conflict (Before)

| Component    | Zone   | Effect |
|-------------|--------|--------|
| Coordinator | zone-b | Cilium blocks GPU worker → coordinator traffic |
| GPU Workers | zone-a | Allocated GPU, can't start training — connection refused |
| Utilization | ~40%   | GPUs idle while waiting for coordinator |

## The Fix (After)

```yaml
# Added to coordinator Deployment:
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: [zone-a]

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ml-training
```

## Key Prometheus Queries

```promql
# GPU utilization
gpu_demo_utilization_pct

# Coordinator in wrong zone (1 = conflict, 0 = OK)
gpu_demo_coordinator_zone

# Workers stuck
gpu_demo_pending_workers

# Scheduling conflict score
gpu_demo_conflict_score
```

## Tear down

```bash
kind delete cluster --name kubeflow-cilium-demo
```
