---
title: "When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes"
published: false
description: "Every pod Running, no errors — yet 60% of GPUs sit idle. The culprit isn't Kubeflow or Cilium, but the gap between a topology-blind scheduler and a topology-aware CNI. Here's how we found it and fixed it in a few lines of YAML."
tags: kubernetes, cilium, kubeflow, mlops
---

<!--
PUBLISHING NOTES (delete these lines when pasting into dev.to):
- CNCF is the CANONICAL home. CNCF accepted this as a community post (under Golden
  Kubestronaut status); scheduled to publish 2026-07-23 ~4:30am PDT.
- CNCF's editor-preferred title is "When Kubeflow MEETS Cilium..." — decide whether to
  match that here or keep "Fights" (the talk/recording title). Either is fine; the
  canonical_url is what dedupes, not the title.
- HOLD publishing until the CNCF post is live (2026-07-23), then publish this as a
  cross-post with canonical_url set to the CNCF post URL.
- Add a cover image via the dev.to editor (Grafana 40%->85% arc, or the concert-hall metaphor image).
- Tags are capped at 4 by dev.to.
-->

> By Ramkumar Nagaraj & Bingi Narasimha Karthik (Adobe)
> 📺 Talk recording (KubeCon + CloudNativeCon India 2026): https://www.youtube.com/watch?v=BG9XGouyM9c
> 🧪 Reproducible lab: https://github.com/ram2valar/kubeflow-cilium-lab

## The symptom that made no sense

The first time we saw it, we didn't trust the dashboard. A distributed training job was scheduled and healthy — every pod Running, no crashes, no OOMKills, nothing in the logs. And yet more than half the GPUs we were paying for sat idle, and training never actually started. Every health check was green, and nothing was computing.

## A metaphor that finally made it click

We kept reaching for a way to explain it, and this is the one that stuck. Imagine a sold-out concert hall. Every musician is in their seat, instruments tuned, the hall lit. But the conductor was shown to the wrong wing of the building — and the fire-safety doors, doing exactly their job, sealed that wing off. The result is a full, expensive hall and complete silence.

That is a GPU cluster in this failure mode. The conductor is the training coordinator. The musicians are the GPU workers, who can only play in sync, through the conductor — the same way distributed training synchronizes gradients through a coordinator. And the fire doors are the network policy: a correct, intentional safety rule that nobody told the scheduler about.

## The root cause: two correct systems, collectively wrong

Kubernetes scheduling is topology-agnostic by design. It places pods based on available resources — CPU, memory, GPU count — without reasoning about which availability zone a pod lands in. Kubeflow inherits that assumption.

Cilium, on the other hand, is topology-aware. Operators use `CiliumNetworkPolicy` to draw zone boundaries for blast-radius isolation, compliance, cost control, or to protect an expensive dedicated GPU pool. That's good security hygiene — and Cilium can't reschedule a pod that has already been placed.

Put those two together and you get a class of problem where each system makes an individually correct decision, and together they're wrong. The coordinator lands in one zone, the GPU workers in another, and the network silently blocks the connection between them. No one holds the single map that shows both the pod placement and the locked doors at once.

## It's a spectrum, not a single bug

What surprised us most is that the same root cause shows up three different ways in production:

1. **Hard block.** A zone-boundary network policy denies the connection outright. Workers can't reach the coordinator and training never starts. You notice in seconds.
2. **Cross-zone latency.** With no hard block, just distance, gradient synchronization (NCCL AllReduce) pays cross-zone round-trip time on every step. Throughput quietly drops 30–60% with no error at all. You notice in hours, if you're paying attention.
3. **Cross-AZ egress cost.** The traffic crosses availability zones and shows up only on the cloud bill as inter-AZ data transfer. You notice in days, on the invoice.

The demo we built reproduces the first case because it fails cleanly and visibly. But the second and third are the ones that quietly drain budgets in real clusters.

## The fix

The surprise is how little you have to change. We didn't touch Cilium — the locked doors stay locked, because the security policy was never the problem. And we didn't patch Kubernetes or Kubeflow. We simply gave the scheduler the one piece of information it was missing: keep the whole training group together, in a zone whose network path is open.

In practice that's a few lines of Kubernetes-native YAML on the workload spec: `nodeAffinity` to pin the group to the GPU zone, `topologySpreadConstraints` to co-locate the coordinator and workers, and a toleration so the coordinator can actually land on the GPU-tainted nodes. Once every communicating pod shares a zone, the traffic is intra-zone — the hard block disappears, the latency disappears, and the cross-AZ egress disappears. One fix, all three symptoms.

If you don't want to hard-code a zone name, `podAffinity` with a zone topology key achieves the same thing by relationship: place the workers in whatever zone the coordinator landed in. Same idea, portable across clusters.

In our lab, GPU utilization went from around 40% to around 85% the moment the group was co-located.

## What we took away

- **Your CNI has opinions about topology that your scheduler can't see.** Topology-aware network policies are silent to the Kubernetes scheduler — and that silence is where the failure lives.
- **The fix is Kubernetes-native.** No CNI change, no framework patch — just topology spread constraints and affinity in the workload spec.
- **Instrument before you need it.** GPU utilization and pod-zone metrics in Prometheus and Grafana exposed this for us in seconds; without them it can take days.
- **The pattern generalizes.** Any topology-aware CNI plus any distributed ML framework can hit the same wall. It isn't specific to Cilium or Kubeflow.

## Try it yourself

We packaged the whole thing as a reproducible lab — a kind cluster with GPU and CPU zones, the Cilium policy, Prometheus recording rules, a Grafana dashboard, and before/after demo scripts:

- Repo: https://github.com/ram2valar/kubeflow-cilium-lab
- Talk recording (KubeCon + CloudNativeCon India 2026): https://www.youtube.com/watch?v=BG9XGouyM9c

Spin it up, watch the GPUs go idle, apply the fix, and watch them come back.
