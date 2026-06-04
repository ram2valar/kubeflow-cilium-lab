# Demo Day Checklist — KubeCon India 2026

**Session:** 19 June 2026 | 12:40–1:10pm IST | Lotus 1 (Level 3)
**Slot:** 30 minutes (25 min talk + 5 min Q&A)
**Fallback:** `recordings/demo-before.mp4` + `recordings/demo-after.mp4` — switch in ~10 seconds

---

## Night Before (18 June, hotel room)

```bash
# 1. Confirm cluster is alive
kind get clusters
# Expected: kubeflow-cilium-demo

kubectl get nodes -L topology.kubernetes.io/zone,gpu
# Expected: 5 nodes — control-plane, 2×zone-a gpu=true, 2×zone-b gpu=false

# 2. Confirm all pods healthy
kubectl get pods -n kube-system | grep cilium
# Expected: 5 cilium pods Running, 2 cilium-operator Running

kubectl get pods -n monitoring | awk '{print $1,$3}'
# Expected: all Running

# 3. Confirm ml-demo is clean (no leftover workloads)
kubectl get pods -n ml-demo
# Expected: No resources found OR only old completed/failed pods

# 4. Clean the namespace ready for tomorrow
kubectl delete namespace ml-demo --ignore-not-found
kubectl create namespace ml-demo
kubectl label namespace ml-demo app=ml-demo
kubectl apply -f manifests/cilium/topology-network-policy.yaml

# 5. Open dashboards and verify metrics baseline
bash scripts/open-dashboards.sh
# Grafana: http://localhost:3000  (admin/admin)
# Prometheus: http://localhost:9090
```

Open Grafana — confirm dashboard "GPU Scheduling Demo — Kubeflow + Cilium" loads with 8 panels.
Open Prometheus — confirm `gpu_demo_zones_occupied` returns 0 (no pods scheduled yet).

---

## 30 Minutes Before (at venue, in the room)

```bash
# Confirm cluster still alive after travel
kind get clusters
kubectl get nodes

# Restart port-forwards (may have dropped overnight)
bash scripts/open-dashboards.sh
curl -s http://localhost:3000/api/health   # should return {"commit":"...","database":"ok",...}
curl -s http://localhost:9090/-/ready      # should return "Prometheus Server is Ready."
```

**Browser tabs to open:**
1. Grafana dashboard: `http://localhost:3000/d/gpu-scheduling-demo`
2. Prometheus alerts: `http://localhost:9090/alerts`
3. Terminal (full-screen, large font) — ready to run demo-before.sh

**Laptop settings:**
- [ ] Plugged into power (don't risk battery death mid-demo)
- [ ] Display sleep: **Never** (System Settings → Displays → Prevent display sleep)
- [ ] Notifications: Do Not Disturb ON
- [ ] Font size in terminal: 18pt minimum (back rows can't read 12pt)

---

## On Stage — Demo Flow (30-minute slot)

### T+0:00 — Introduction (2 min)
Talk to the problem. No commands yet.

### T+2:00 — Cluster topology slide
Mention: "here's our 5-node lab — 2 GPU nodes in zone-a, 2 CPU nodes in zone-b."

### T+5:00 — Run BEFORE demo
```bash
bash scripts/demo-before.sh
```
The script has a **40-second sleep** after deploying the workload. Use that time to narrate:
> "This is deploying a Kubeflow-style training job — coordinator plus 4 GPU workers. No topology constraints. Let's see where they land."

### T+6:00 — During sleep, switch to Grafana
Open the Grafana dashboard tab. It will start showing data as soon as pods are scheduled.

### T+6:30 — Script shows pod placement
Key output to point to:
```
ml-coordinator → zone: zone-b  (role: coordinator)   ← THE PROBLEM
ml-gpu-workers → zone: zone-a  (role: gpu-worker)    ← 4 workers here
```

### T+7:00 — Script shows worker logs
```
[gpu-worker] *** CANNOT REACH COORDINATOR (attempt 1/24) — GPU IDLE ***
```

> "Workers have GPU resources. They cannot reach the coordinator. Cilium is enforcing the zone boundary."

### T+7:30 — Switch to Grafana tab (**CRITICAL TIMING WINDOW**)
Workers fail at ~T+7:40 (120s after deploy at T+5:40). You have ~10 seconds here.

Point to:
- GPU Utilization gauge: **40%** (red)
- Topology Zones Occupied: **2** (red — "Cross-zone!")
- Coordinator in Wrong Zone: **zone-b (wrong!)** (red)
- GPU Utilization Over Time: flat line at 40%

### T+8:00 — Prometheus alerts
Switch to `http://localhost:9090/alerts`
> "Prometheus fired `GPUWorkersCantReachCoordinator`. This is the smoking gun."

### T+8:30 — Root cause slides (6 min)
Back to slides. No commands.

### T+14:30 — Run AFTER demo
```bash
bash scripts/demo-after.sh
```
25-second sleep — narrate the 3 YAML additions (nodeAffinity, topologySpreadConstraints).

### T+15:30 — Zone verification output
```
ml-coordinator → zone: zone-a ✓
ml-gpu-workers → zone: zone-a ✓ (all four)
```

### T+16:00 — Worker logs (success)
```
[gpu-worker] Connected to coordinator immediately!
[gpu-worker] Training step 1/30 — GPU ACTIVE at ~85%
```

### T+16:30 — Switch to Grafana
- GPU Utilization gauge: **85%** (green)
- Topology Zones Occupied: **1** (green — "Same zone — OK")
- Coordinator in Wrong Zone: **zone-a (correct)** (green)
- GPU Utilization Over Time: jump from 40% to 85%

### T+17:00 — Production spectrum slide (3 min)
"Same root cause in clusters without hard Cilium policies..."

### T+20:00 — Takeaways (4 min)

### T+24:00 — Q&A (5 min)

---

## If the Live Demo Fails

**Failure mode → Recovery action:**

| Problem | Action |
|---------|--------|
| `kind get clusters` returns nothing | Docker not running — `open -a Docker` then wait 30s |
| Port-forward not responding | `bash scripts/open-dashboards.sh` (kills old, starts new) |
| Coordinator lands on zone-a (no conflict) | Rare — re-run `demo-before.sh` (step 0 cleans up) |
| Workers connect immediately (Cilium not blocking) | Cilium policy not propagated — wait 20s and check again |
| Demo time pressure at T+7:30 | **Switch to recorded video immediately** — don't lose the audience |

**Switching to backup video (do this if ANY issue appears):**
1. Say: *"Let me show you this on the pre-recorded run so we can focus on the analysis."*
2. Open `recordings/demo-before.mp4` — play from start
3. Pause at pod placement, at logs, at Grafana showing 40%
4. Open `recordings/demo-after.mp4` — play from start
5. Pause at zone verification, at Grafana showing 85%

This takes ~10 seconds to switch. The audience will not notice.

---

## Key Prometheus Queries (paste into Prometheus if needed)

```promql
# The one query that proves the problem:
gpu_demo_zones_occupied          # BEFORE: 2  AFTER: 1

# Supporting evidence:
gpu_demo_utilization_pct         # BEFORE: 40  AFTER: 85
gpu_demo_coordinator_zone        # BEFORE: 1   AFTER: 0
gpu_demo_conflict_score          # BEFORE: 1.0 AFTER: 0
```

---

## Emergency Contacts

- GitHub repo: https://github.com/ram2valar/kubeflow-cilium-lab
- Session link: https://kccncind2026.sched.com/event/2IW3n
