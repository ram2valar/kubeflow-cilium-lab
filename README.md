# Kubeflow + Cilium GPU Scheduling Demo Lab

**KubeCon India 2026** — "When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes"

> Ramkumar Nagaraj & Bingi Narasimha Karthik

---

## The Problem

Distributed ML training on Kubernetes has a structural coordination gap: **the workload
scheduler and the CNI operate independently**.

**Kubeflow's pipeline scheduler** places coordinator and worker pods based on resource
availability — with no awareness of network topology or availability zone boundaries.

**Cilium** enforces network topology boundaries with eBPF precision — but cannot
influence where pods are scheduled once the decision has been made.

When these two systems make conflicting placement decisions, GPUs are allocated, billed,
and idle. The failure is silent: pods show `Running`, nodes show GPU resources
`Allocated`, and no alert fires without custom instrumentation.

This lab reproduces that conflict and demonstrates the fix.

---

## How This Manifests in Production

The severity depends on whether the cluster enforces hard zone boundaries or has
zone-preference behaviour:

| Scenario | Mechanism | Symptom | Detection |
|----------|-----------|---------|-----------|
| Zone-based `CiliumNetworkPolicy` *(this lab)* | Hard connectivity block between zones | Workers cannot reach coordinator — training never starts | Alert fires; pod logs show connection failures |
| Multi-AZ GPU node pool, no zone policy | Cross-zone NCCL AllReduce adds 1–5 ms per collective | Training runs at 40–60% expected throughput | No error; looks like a slow model or bad data pipeline |
| Cross-AZ egress pricing | Data transfer billed at cloud egress rates (~$0.01/GB) | Cost spike with no performance signal | Cloud billing dashboards, not Kubernetes metrics |

**The fix is identical in all three cases**: topology spread constraints that co-locate
coordinator and workers in the same availability zone.

---

## When Zone-Based Network Policies Exist in Production

The `deny-cross-zone-gpu-traffic` Cilium policy in this lab is not hypothetical. It
represents configurations that appear in production clusters in several contexts:

- **Multi-tenant GPU clusters**: security teams restrict cross-zone traffic to limit
  blast radius between tenants sharing the same GPU infrastructure
- **Compliance and data locality**: regulated ML workloads that must not transmit
  gradients or weights across zone (or region) boundaries
- **Cost-driven CNI policies**: teams that block cross-AZ egress at the CNI layer to
  prevent accidental large-scale data transfer charges
- **Dedicated GPU pool isolation**: GPU nodes locked down so that only explicitly
  labelled workloads can reach them, reducing the risk of resource contention

---

## What This Lab Does

Reproduces a scheduling conflict where a Kubeflow-style coordinator pod lands in `zone-b`
while GPU worker pods are pinned to `zone-a`. Cilium's zone-based network policy blocks
cross-zone traffic, leaving GPUs allocated but idle (~40% utilisation). Applying pod
topology spread constraints resolves the conflict (~85% utilisation).

This demonstrates the worst-case manifestation of the topology mismatch. The lab is
designed so the problem is unambiguous and reproducible in under 30 minutes on a laptop.

---

## Prerequisites

- Docker
- `kind`
- `kubectl`
- `helm`

---

## Quick Start

```bash
# 1. Bring up the full environment (~10 min)
bash scripts/setup.sh

# 2. Open Grafana + Prometheus dashboards
bash scripts/open-dashboards.sh
#    Grafana:    http://localhost:30080  (admin/admin)
#    Prometheus: http://localhost:30090
#    Dashboard:  "GPU Scheduling Demo — Kubeflow + Cilium"

# 3. Run the BEFORE demo — shows the scheduling conflict
bash scripts/demo-before.sh
#    Grafana shows ~40% GPU utilisation, conflict alert fires

# 4. Run the AFTER demo — applies the topology spread fix
bash scripts/demo-after.sh
#    Grafana shows ~85% GPU utilisation, conflict resolved

# 5. Tear down when done
bash scripts/teardown.sh
```

---

## Lab Architecture

```
kind cluster: kubeflow-cilium-demo
├── control-plane
├── worker (zone-a, gpu=true, taint: gpu=present:NoSchedule)  ×2
└── worker (zone-b, gpu=false)                                 ×2

Installed:
├── Cilium        CNI with zone-based network policy (deny-cross-zone-gpu-traffic)
├── Prometheus    Custom GPU scheduling recording rules + alerts
└── Grafana       Dashboard auto-imported via ConfigMap

Note: GPU workloads are simulated with busybox (coordinator + worker jobs).
      Scheduling behaviour is identical to real GPU workloads.
      GPU node exclusivity is simulated via node taints (gpu=present:NoSchedule).
```

---

## The Conflict (Before)

| Component | Zone | Pod Label | Effect |
|-----------|------|-----------|--------|
| Coordinator | zone-b (falls to CPU nodes — no GPU taint toleration) | `zone: zone-b` | Cilium policy blocks inbound from GPU workers |
| GPU Workers | zone-a (pinned via nodeSelector + taint toleration) | `zone: zone-a` | Egress restricted to `zone: zone-a` endpoints only |
| Utilisation | — | — | ~40% — GPUs allocated, training stalled |

**Why the coordinator lands in zone-b**: GPU nodes carry `gpu=present:NoSchedule`.
Without a toleration, the coordinator cannot schedule on GPU nodes and falls to CPU-only
zone-b nodes. Kubeflow does not add topology constraints by default.

**Why Cilium blocks the connection**: `deny-cross-zone-gpu-traffic` restricts
`role: gpu-worker` pod egress to endpoints with `zone: zone-a`. The coordinator carries
`zone: zone-b`, so workers are blocked from reaching it.

**Why this is hard to detect without instrumentation**: GPUs show `Allocated` in
`kubectl describe node`. Pods show `Running`. No OOMKill, no CrashLoopBackOff, no
scheduler event. Without the `gpu_demo_zones_occupied` or `gpu_demo_coordinator_zone`
recording rules, the failure is invisible at the Kubernetes layer.

## The Fix (After)

```yaml
# Added to coordinator Deployment spec:
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: [zone-a]   # pin coordinator to GPU zone

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ml-training         # all ml-training pods must share a zone
```

The coordinator is now pinned to zone-a nodes, carries `zone: zone-a`, and is reachable
from GPU workers. Cilium's intra-zone policy allows all traffic. Utilisation rises to ~85%.

The GPU worker manifest adds a second spread constraint for intra-zone node distribution:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ml-training
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname   # spread across nodes within zone-a
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        role: gpu-worker
```

---

## Key Prometheus Queries

```promql
# GPU utilisation (expect ~40% before fix, ~85% after)
gpu_demo_utilization_pct

# Distinct topology zones occupied by ml-demo pods (> 1 = cross-zone conflict)
# This metric works regardless of whether a hard Cilium policy is in place —
# it detects the scheduling mismatch at the node topology layer.
gpu_demo_zones_occupied

# Coordinator in wrong zone — relies on pod label (1 = conflict, 0 = resolved)
gpu_demo_coordinator_zone

# Workers stuck in Pending
gpu_demo_pending_workers

# Scheduling conflict score (1.0 = full conflict, 0.0 = resolved)
gpu_demo_conflict_score
```

---

## Repo Contents

```
docs/
└── production-context.md   Spectrum of manifestations + diagnostic runbook

manifests/
├── before/         GPU workload WITHOUT topology constraints (the problem)
├── after/          GPU workload WITH topology constraints (the fix)
├── cilium/         Zone-based Cilium network policy
└── monitoring/     Prometheus rules, Grafana dashboard, Helm values

scripts/
├── setup.sh              Full cluster + monitoring setup
├── open-dashboards.sh    Port-forward Grafana (30080) + Prometheus (30090)
├── demo-before.sh        Reproduce the scheduling conflict
├── demo-after.sh         Apply the fix and show resolution
├── install-kfp.sh        Optional: install Kubeflow Pipelines (~8 GiB RAM)
└── teardown.sh           Delete the kind cluster

recordings/
├── demo-before.mp4       Recorded backup of the BEFORE demo
└── demo-after.mp4        Recorded backup of the AFTER demo
```

---

## Talk Details

- **Event:** KubeCon India 2026 | 19 June 2026 | 12:40–1:10 pm IST
- **Room:** Lotus 1 (Level 3)
- **Slide upload deadline:** 10 June 2026
- **Repo:** https://github.com/ram2valar/kubeflow-cilium-lab
