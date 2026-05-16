# Kubeflow + Cilium GPU Scheduling Demo Lab

**KubeCon India 2026** — "When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes"

> Speaker: Ramkumar Nagaraj | Sr. Computer Scientist, Adobe
> Slides & proposal: see repo root

---

## What this lab does

Reproduces a scheduling conflict where a Kubeflow-style coordinator pod lands in zone-b
while GPU worker pods are in zone-a. Cilium's zone-based network policy blocks cross-zone
traffic, leaving GPUs allocated but idle (~40% utilization). Applying pod topology spread
constraints resolves the conflict (~85% utilization).

---

## Prerequisites

- Docker
- `kind`
- `kubectl`
- `helm`

---

## Quick Start

```bash
# 1. Bring up the full environment (takes ~10 min)
bash scripts/setup.sh

# 2. Open Grafana + Prometheus dashboards
bash scripts/open-dashboards.sh
#    Grafana:    http://localhost:3000  (admin/admin)
#    Prometheus: http://localhost:9090
#    Dashboard:  "GPU Scheduling Demo — Kubeflow + Cilium"

# 3. Run the BEFORE demo — shows the scheduling conflict
bash scripts/demo-before.sh
#    Grafana shows ~40% GPU utilization, conflict alert fires

# 4. Run the AFTER demo — applies the topology spread fix
bash scripts/demo-after.sh
#    Grafana shows ~85% GPU utilization, conflict resolved

# 5. Tear down when done
bash scripts/teardown.sh
```

---

## Lab Architecture

```
kind cluster: kubeflow-cilium-demo
├── control-plane
├── worker-zone-a-gpu-1   (zone-a, gpu=true, taint: gpu=present:NoSchedule)
├── worker-zone-a-gpu-2   (zone-a, gpu=true, taint: gpu=present:NoSchedule)
├── worker-zone-b-cpu-1   (zone-b, gpu=false)
└── worker-zone-b-cpu-2   (zone-b, gpu=false)

Installed:
├── Cilium              CNI with zone-based network policy (deny-cross-zone-gpu-traffic)
├── Prometheus          Metrics with custom GPU scheduling recording rules + alerts
└── Grafana             Dashboard auto-imported via ConfigMap

Note: GPU workloads are simulated with busybox (coordinator + worker jobs).
      Scheduling behaviour is identical to real GPU workloads.
```

---

## The Conflict (Before)

| Component    | Zone   | Effect |
|-------------|--------|--------|
| Coordinator | zone-b | Cilium blocks GPU worker → coordinator traffic |
| GPU Workers | zone-a | Allocated GPU, can't reach coordinator — training stalled |
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
              values: [zone-a]   # ← pin coordinator to GPU zone

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ml-training         # ← all ml-training pods in same zone
```

---

## Key Prometheus Queries

```promql
# GPU utilization (expect ~40% before fix, ~85% after)
gpu_demo_utilization_pct

# Coordinator in wrong zone (1 = conflict, 0 = resolved)
gpu_demo_coordinator_zone

# Workers actually stuck in Pending
gpu_demo_pending_workers

# Scheduling conflict score (1 = conflict, 0 = resolved)
gpu_demo_conflict_score
```

---

## Repo Contents

```
manifests/
├── before/         GPU workload WITHOUT topology constraints (the problem)
├── after/          GPU workload WITH topology constraints (the fix)
├── cilium/         Zone-based Cilium network policy
└── monitoring/     Prometheus rules, Grafana dashboard, Helm values

scripts/
├── setup.sh        Full cluster + monitoring setup
├── open-dashboards.sh  Port-forward Grafana (3000) + Prometheus (9090)
├── demo-before.sh  Reproduce the scheduling conflict
├── demo-after.sh   Apply the fix and show resolution
└── teardown.sh     Delete the kind cluster

recordings/
├── demo-before.mp4  Recorded backup of the BEFORE demo
└── demo-after.mp4   Recorded backup of the AFTER demo (trimmed)
```

---

## Talk Details

- **Event:** KubeCon India 2026 | 18–19 June 2026
- **Slide upload deadline:** 10 June 2026
- **Repo:** https://github.com/ram2valar/kubeflow-cilium-lab
