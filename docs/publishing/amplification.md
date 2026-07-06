# Amplification blurbs (post AFTER the canonical blog is live)

Sequencing: publish the canonical post first (CNCF blog if accepted, else dev.to),
then use these to drive traffic to it. Lead these with the story/lab, not "read my blog."

---

## r/kubernetes

Subreddit rules favor technical substance over self-promo — this leads with the
problem and the open-source lab, which is why it fits.

**Title:**
> Every pod Running, no errors — yet 60% of our GPUs sat idle. It was topology-blind scheduling meeting a topology-aware CNI.

**Body:**
> We hit a distributed-training failure where every pod was Running and healthy, no errors or OOMKills, but ~60% of GPUs were idle and training never started. Root cause: the scheduler places pods by resources (topology-agnostic), while Cilium enforces zone boundaries (topology-aware). The coordinator landed in a different zone than the GPU workers, and the network silently blocked the connection.
>
> The fix was Kubernetes-native — topology spread constraints + nodeAffinity to co-locate the training group — no Cilium or Kubeflow changes. The same root cause also shows up in prod as cross-zone NCCL latency (30–60% slower, no error) and cross-AZ egress cost.
>
> Built a fully reproducible kind-based lab (Cilium policy, Prometheus rules, Grafana dashboard, before/after scripts): https://github.com/ram2valar/kubeflow-cilium-lab
> Full write-up: <CANONICAL BLOG URL>
> Talk recording: https://www.youtube.com/watch?v=BG9XGouyM9c

---

## Hacker News (Show HN)

**Title:**
> Show HN: A reproducible lab for the Kubeflow/Cilium GPU-idle scheduling bug

**URL:** https://github.com/ram2valar/kubeflow-cilium-lab

**First comment (post immediately after submitting):**
> Author here. We kept hitting a confusing failure: distributed GPU training scheduled and "healthy" — every pod Running, no errors — but GPUs ~60% idle and training stalled. It turned out to be a gap between two individually-correct systems: the Kubernetes scheduler is topology-agnostic (places pods by CPU/mem/GPU), while Cilium enforces zone-boundary network policy. The coordinator landed in a different zone than the workers, and the network silently blocked them.
>
> This repo reproduces it end to end on a kind cluster (GPU + CPU zones, Cilium policy, Prometheus recording rules, Grafana dashboard) and shows the fix: topology spread constraints + nodeAffinity to co-locate the group — no Cilium or Kubeflow patch. Utilization goes ~40% → ~85%.
>
> Write-up: <CANONICAL BLOG URL> · Talk: https://www.youtube.com/watch?v=BG9XGouyM9c
> Happy to answer questions.

---

## Community Slacks (drop the canonical link)

- **Cilium & eBPF Slack** (`#blog` / `#general`): frame it as "Cilium policy did exactly the right thing; the gap was scheduler awareness" — they like that framing.
- **Kubeflow Slack** (`#kubeflow-discuss`): frame it as a Kubeflow scheduling/topology story + reproducible lab.

## X / Bluesky (short)

> Every pod Running, no errors — yet 60% of our GPUs sat idle. The culprit wasn't Kubeflow or Cilium; it was the gap between a topology-blind scheduler and a topology-aware CNI. Fix = a few lines of K8s-native YAML. Lab + write-up 👇
> <CANONICAL BLOG URL>
