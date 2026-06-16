# Demo Diagrams

Visual explainers for the talk **"When Kubeflow Fights Cilium: Debugging 60% Idle
GPUs in Kubernetes"** (KubeCon India 2026). Each diagram is provided as **SVG**
(vector — scales cleanly on a projector and imports into slides) and **PNG**
(1600px raster for quick preview).

| Diagram | What it shows |
|---------|---------------|
| `01-hero-before-after` | The 5-node cluster, BEFORE vs AFTER. BEFORE: coordinator stranded in zone-b, Cilium drops cross-zone traffic, GPUs ~40% idle. AFTER: coordinator co-located in zone-a, intra-zone traffic allowed, ~85% utilisation. |
| `02-scheduler-decision` | The kube-scheduler filter funnel for the coordinator pod. How `nodeAffinity` picks the zone, the GPU-taint toleration unlocks the nodes, and `topologySpreadConstraints` guards co-location. |
| `03-metrics-pipeline` | The observability path: pods → kube-state-metrics → Prometheus recording rules → Grafana + alerts, with the metric math (utilisation 40 → 85) and scrape-lag notes. |
| `04-runbook-timeline` | The 30-minute stage run-of-show, with the two live-demo timing windows and the recorded-video fallback. |

## Regenerating the PNGs

The PNGs are rendered from the SVGs. On macOS (no extra dependencies):

```bash
cd docs/diagrams
for f in *.svg; do sips -s format png "$f" --out "${f%.svg}.png"; done
```
