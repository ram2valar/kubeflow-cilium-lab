# When Kubeflow Fights Cilium: Debugging 60% Idle GPUs

> Companion write-up for the KubeCon + CloudNativeCon India 2026 talk by
> Ramkumar Nagaraj & Bingi Narasimha Karthik (Adobe).
> 📺 Recording: https://www.youtube.com/watch?v=BG9XGouyM9c
> Session: https://kccncind2026.sched.com/event/2IW3n/when-kubeflow-fights-cilium-debugging-60-idle-gpus-in-kubernetes-ramkumar-nagaraj-bingi-narasimha-karthik-adobe
> Reproducible lab: https://github.com/ram2valar/kubeflow-cilium-lab

## The symptom that makes no sense

Your distributed training job is scheduled. Every pod is `Running`. There are no
crashes, no `OOMKilled`, no kernel errors. And yet your GPUs sit ~60% idle while
training never makes progress. Every health check is green — and nothing computes.

## The metaphor

Imagine a sold-out concert hall. Every musician is seated, instruments tuned, the
hall lit. But the conductor was shown to the wrong wing — and the fire-safety doors,
doing exactly their job, sealed that wing off. The result: a full, expensive hall,
and total silence.

That is your GPU cluster. The conductor is the coordinator pod, the musicians are
the GPU workers (who can only play *in sync, through the conductor* — just as
distributed training synchronizes gradients through the coordinator), and the fire
doors are Cilium's network policy: a *correct* safety rule that nobody told the
scheduler about.

## The root cause

Two systems, each individually correct, are collectively wrong:

- **The scheduler is topology-agnostic.** Kubernetes places pods by available
  resources — CPU, memory, GPU count — not by which availability zone they land in.
  Kubeflow inherits that assumption.
- **Cilium is topology-aware.** It enforces zone boundaries via `CiliumNetworkPolicy`
  (for blast-radius isolation, compliance, cost control, or dedicated GPU-pool
  protection). It cannot reschedule a pod that's already been placed.

The gap between them strands the coordinator in a different zone from the GPU
workers, and the network silently blocks the connection. Nobody holds the map that
shows both the seating plan and the locked doors at once.

## It's a spectrum, not a single bug

The same cross-zone placement shows up three ways in production:

1. **Hard block** — a zone-boundary network policy *denies* the connection; workers
   can't reach the coordinator and training never starts. Detected in seconds.
2. **Cross-zone NCCL latency** — no hard block, just distance; AllReduce pays
   cross-zone round-trip time and throughput drops 30–60% with no error at all.
   Detected in hours.
3. **Cross-AZ egress cost** — invisible to Kubernetes; surfaces only on the cloud
   bill as inter-AZ data-transfer charges. Detected in days.

See [docs/production-context.md](production-context.md) for the full diagnostic
runbook for each scenario.

## One fix resolves all three

Co-locate the whole training group in one zone. No Kubeflow patch. No Cilium change.
Just topology-aware scheduling on the workload spec:

```yaml
# On the coordinator (and the whole ml-training group):
affinity:
  nodeAffinity:                                   # pin to the GPU zone
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: [zone-a]
topologySpreadConstraints:                        # keep the group co-located
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels: { app: ml-training }
tolerations:                                      # so it can land on GPU-tainted nodes
  - key: gpu
    value: present
    effect: NoSchedule
```

A portable variant — co-locate by relationship rather than a hard-coded zone name —
uses `podAffinity` with `topologyKey: topology.kubernetes.io/zone` to put the group
in whatever zone the coordinator landed in.

The scheduler was always topology-capable — `topologySpreadConstraints` and
`nodeAffinity` are native Kubernetes. It just needed to be told to care.

## Reproduce it yourself

The full lab is in this repo: a 5-node kind cluster (GPU-tainted zone-a + CPU
zone-b), Cilium with a zone-based network policy, Prometheus recording rules, a
Grafana dashboard, and before/after demo scripts.

```bash
bash scripts/setup.sh            # build the cluster + monitoring
bash scripts/open-dashboards.sh  # Grafana :3000, Prometheus :9090
bash scripts/demo-before.sh      # reproduce the conflict (~40% GPU)
bash scripts/demo-after.sh       # apply the fix (~85% GPU)
```

## Takeaways

- Your CNI has opinions about topology that your scheduler can't see.
- Topology spread constraints are the Kubernetes-native fix — no CNI or framework changes.
- Instrument for it before you need it: GPU utilization + pod-zone metrics expose this in seconds, not days.
- The pattern applies to any topology-aware CNI plus any distributed ML framework — not just Cilium and Kubeflow.
