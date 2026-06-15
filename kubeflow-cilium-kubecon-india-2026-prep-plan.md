# KubeCon India 2026 – Presentation & Demo Prep Plan

**Talk:** When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes  
**Event:** KubeCon India 2026 | **Dates:** 18–19 June 2026  
**Slide upload deadline:** 10 June 2026  
**Session length:** Assume 45–55 minutes (confirm with organizers)

---

## Timeline Overview

| Phase | Focus | Target completion | Status |
|-------|--------|-------------------|--------|
| 1 | Lab setup & demo viability | End of April 2026 | ✅ COMPLETE |
| 2 | Slide outline & first draft | Mid-May 2026 | ✅ COMPLETE |
| 3 | Demo script & recorded backup | End of May 2026 | ✅ COMPLETE |
| 4 | Rehearsals & timing | 1–7 June 2026 | ⏳ PENDING |
| 5 | Final slides & upload | **10 June 2026** | ⏳ PENDING |
| 6 | Event week prep | 10–17 June 2026 | ⏳ PENDING |

---

## Phase 1: Lab Setup & Demo Viability ✅ COMPLETE

**Goal:** Reproduce the problem and fix in a real environment so the story and demo are credible.

### 1.1 Lab environment

- [x] Stand up a Kubernetes cluster — 5-node kind cluster (zone-a: 2 GPU-tainted nodes, zone-b: 2 CPU nodes, 1 control-plane), Cilium CNI
- [x] Install and configure Kubeflow-style workloads (simulated with busybox coordinator + GPU worker jobs)
- [x] Install Cilium as CNI with zone-based network topology policy (`deny-cross-zone-gpu-traffic`)
- [x] Add Prometheus + Grafana for metrics (kube-prometheus-stack)
- [x] Document node roles, GPU allocation, and workload setup

### 1.2 Reproduce the problem

- [x] BEFORE workload: coordinator lands in zone-b, GPU workers in zone-a, Cilium blocks traffic → workers idle
- [x] Captured before metrics: GPU utilization ~40% (allocated but blocked), conflict score = 1, alerts firing
- [x] Demo script `scripts/demo-before.sh` verified end-to-end

### 1.3 Apply the fix

- [x] Fix: `nodeAffinity` + `topologySpreadConstraints` pin coordinator to zone-a (same zone as GPU workers)
- [x] AFTER workload: all pods in zone-a → Cilium allows traffic → workers connect → training at 85%
- [x] Demo script `scripts/demo-after.sh` verified end-to-end

### 1.4 Prometheus / diagnostics

- [x] PrometheusRule with recording rules: `gpu_demo_utilization_pct`, `gpu_demo_workers_connected`, `gpu_demo_coordinator_zone`, `gpu_demo_conflict_score`, etc.
- [x] Alerts: `GPUUtilizationCriticallyLow`, `GPUWorkersCantReachCoordinator`
- [x] Grafana dashboard: GPU Utilization %, GPU Idle %, Scheduling Conflict Score, Coordinator Zone panel, time-series arc

### 1.5 GitHub repo

- [x] Repo created: https://github.com/ram2valar/kubeflow-cilium-lab
- [x] README, manifests, scripts, Grafana dashboard, Prometheus rules all pushed
- [ ] Final PPTX to be pushed once animations/storytelling tweaks are done

---

## Phase 2: Slide Outline & First Draft ✅ COMPLETE

**Goal:** Full deck that matches the proposal and supports the live demo.

### 2.1 Slide deck

- [x] Built using KubeCon India 2026 branded PowerPoint template
- [x] File: `/Users/ranagara/Documents/cncf-europe-india-2026-proposals/kubecon-india-2026-kubeflow-cilium.pptx`
- [x] 19 slides (added "Beyond the Hard Block: The Production Spectrum" slide; count also increased after image alignment)
- [x] Speakers: Ramkumar Nagaraj | Sr. Computer Scientist, Adobe **+ Bingi Narasimha Karthik | Computer Scientist II, Adobe** (co-speaker, on title slide)
- [x] Slide order: Title → Agenda → §1 Problem → Topology → Conflict → Demo BEFORE → §2 Root Cause → Cilium Policy → Alert → §3 Fix → YAML Fix → Demo AFTER → Before/After Numbers → Arc Chart → Production Spectrum → Takeaways → Q&A
- [x] Repo link on last slide updated to: `github.com/ram2valar/kubeflow-cilium-lab`
- [x] Content QA passed

### 2.2 In progress

- [x] Animations — sequential fade-in-on-click reveals added to 9 content slides (2, 4, 5, 9, 10, 13, 15, 17, 19) on 2026-06-15; titles/dividers/image slides/Questions left static. **Verify build pacing in Slideshow mode (PDF can't show animations).**
- [ ] Storytelling tweaks (optional, ongoing)
- [ ] Final PPTX to be pushed to GitHub repo once done

### 2.3 Content corrections (2026-06-15)

- [x] Slide 15 (Before/After Numbers): fixed training progress `60/60` → `30/30 steps` (matches 30-step demo loop)
- [x] Slide 10 (Smoking Gun): added `gpu_demo_zones_occupied returns 2` to Prometheus signals
- [x] Slide 18 (Takeaways): takeaway 4 now names the 3 production scenarios
- [x] New slide 17 "Beyond the Hard Block: The Production Spectrum" — hard Cilium block / cross-zone NCCL latency / cross-AZ egress cost, one fix for all three (from `docs/production-context.md`)
- [x] Title slide: added co-speaker Bingi Narasimha Karthik
- [x] Last slide (Questions): github link centered at top + two QR profile cards side by side (Ramkumar left, Karthik right). Note: QR card JPEGs have black letterboxing; Ramkumar's card headline shows a placeholder ("Cloud hmmmmmm…") — regenerate if desired

---

## Phase 3: Demo Script & Recorded Backup ✅ COMPLETE

**Goal:** Reliable live demo + a recorded backup if Wi‑Fi or cluster fails.

### 3.1 Demo script

- [x] `scripts/demo-before.sh` — reproduces scheduling conflict (coordinator zone-b, workers blocked, 40% utilization, alerts firing)
- [x] `scripts/demo-after.sh` — applies topology spread fix (all pods zone-a, workers train, 85% utilization, conflict resolved)
- [x] `scripts/open-dashboards.sh` — port-forwards Grafana (3000) and Prometheus (9090)
- [x] `scripts/setup.sh` / `scripts/teardown.sh` for full cluster lifecycle

### 3.2 Recorded backup

- [x] `recordings/demo-after.mp4`
- [x] `recordings/demo-before.mp4`

### 3.3 Demo environment

- [x] Live cluster: kind on MacBook Pro (KUBECONFIG: `~/.kube/config`, context: `kind-kubeflow-cilium-demo`)
- [x] Fallback: recorded video `demo-before.mp4` and `demo-after.mp4`
- [x] Demo flow tested: `open-dashboards.sh` → `demo-before.sh` → `demo-after.sh`
- [x] Cluster resources cleaned up (2026-05-16): ml-demo namespace deleted, Prometheus TSDB wiped — ready for rehearsal run

---

## Phase 4: Rehearsals & Timing (1–7 June 2026) ⏳ PENDING

**Goal:** On-time, smooth delivery and confident handling of demo.

### 4.1 Rehearsals

- [ ] Full run-through at least 2 times (slides + live demo)
- [ ] One rehearsal with co-speaker Karthik: who speaks which section, who drives the demo
- [ ] One dry run as if at the venue: same laptop, same network (or backup video)

**To start a rehearsal run:**
```bash
bash scripts/open-dashboards.sh   # Grafana: localhost:3000  Prometheus: localhost:9090
bash scripts/demo-before.sh       # Reproduce the conflict
bash scripts/demo-after.sh        # Apply the fix
```

### 4.2 Timing

- [ ] Time each section; stay within session length (45 min talk + 10 min Q&A)
- [ ] If over: cut Context or Research setup detail; keep problem → cause → fix → demo → takeaways
- [ ] Plan buffer: "If demo fails at minute 25, switch to recorded video and continue from Results slide"

### 4.3 Q&A prep

- [ ] Prepare answer for: "Does this work at 500 nodes vs your 3-node kind cluster?"
- [ ] List 5–10 likely questions (e.g. "Does this apply to non-GPU?" "What about other CNIs?" "Scale limits?")
- [ ] Prepare short answers (2–3 sentences each)
- [ ] Have GitHub repo URL ready: `github.com/ram2valar/kubeflow-cilium-lab`

---

## Phase 5: Final Slides & Upload (deadline 10 June 2026) ⏳ PENDING

**Goal:** Polished deck uploaded by the deadline.

### 5.1 Slide polish

- [x] Animations done (2026-06-15); storytelling tweaks optional/ongoing
- [ ] Confirm all links working (GitHub repo URL correct on last slide ✓)
- [ ] Speaker notes with demo cues and timing

### 5.2 Export and upload

- [ ] Push final PPTX to `ram2valar/kubeflow-cilium-lab` GitHub repo
- [ ] Export as PDF (backup)
- [ ] **Upload to KubeCon portal by 10 June 2026**
- [ ] Confirm receipt (email or portal confirmation)

### 5.3 Backup copy

- [ ] Keep a copy in cloud and on USB; same version as uploaded

---

## Phase 6: Event Week (10–17 June 2026) ⏳ PENDING

**Goal:** Logistics and last-mile prep; no surprises on stage.

### 6.1 Logistics

- [ ] Confirm day and time of session (18 or 19 June)
- [ ] Confirm room and AV: HDMI/USB-C, mic, clicker
- [ ] Plan arrival at venue with buffer (e.g. 30 min before session)

### 6.2 Tech checklist

- [ ] Laptop charged; dongles for HDMI/USB-C
- [ ] Demo: kind cluster running on laptop OR recorded video ready as fallback
- [ ] Slides on laptop (in case event system fails)
- [ ] GitHub repo live: https://github.com/ram2valar/kubeflow-cilium-lab

### 6.3 Day-of

- [ ] Test display and audio in the room before your slot
- [ ] If live demo: quick test (`kubectl get nodes --context kind-kubeflow-cilium-demo` or open Grafana at localhost:3000)
- [ ] Introduce yourself and follow the script

---

## Deliverables Checklist (from proposal)

| Deliverable | By when | Status |
|-------------|---------|--------|
| GitHub repo (manifests, configs, README) | Before event; link in slides | ✅ https://github.com/ram2valar/kubeflow-cilium-lab |
| Prometheus queries / Grafana dashboard | Phase 1; add to repo | ✅ In repo |
| Recorded demo video | End of May (backup) | ✅ `demo-before.mp4` and `demo-after.mp4` |
| Final PPTX in repo | Before slide upload | ⏳ Pending animations/tweaks |
| Slide upload to KubeCon portal | **10 June 2026** | ⏳ Pending |
| Reproducibility / runbook | Before or after event | ✅ `scripts/setup.sh` + README |

---

## Open Items

| Item | Owner | Notes |
|------|-------|-------|
| Co-speaker | Ramkumar | ✅ Confirmed: Bingi Narasimha Karthik (Computer Scientist II, Adobe); on title slide |
| Slide animations | Ramkumar | ✅ Done 2026-06-15 (verify pacing in Slideshow); storytelling tweaks optional |
| Rehearsals | Ramkumar + Karthik | 1–7 June |
| Slide upload | Ramkumar | Hard deadline: 10 June |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Live demo fails (network, cluster down) | `recordings/demo-before.mp4` and `recordings/demo-after.mp4` ready; switch in 10 seconds |
| Session shorter than planned | Mark "optional" slides; be ready to drop Context/Research setup detail |
| Co-speaker (Karthik) unavailable | Either speaker can do full talk solo; other joins for Q&A if possible |
| Laptop/AV issues | PDF of slides on USB; present from event machine if needed |
| kind cluster not running at venue | All workloads scripted; `setup.sh` + `demo-before.sh` + `demo-after.sh` reproducible in ~10 min |

---

## Quick Reference – Key Dates

- ~~**End April 2026:** Lab working; problem + fix reproducible; metrics and configs saved.~~ ✅
- ~~**Mid-May 2026:** First full slide draft; demo script written.~~ ✅
- ~~**End May 2026:** Rehearsals started; recorded backup demo done.~~ ✅
- **1–7 June 2026:** Final rehearsals; timing locked.
- **10 June 2026:** **Slides uploaded. ← HARD DEADLINE**
- **10–17 June 2026:** Logistics and tech check.
- **18–19 June 2026:** **KubeCon India 2026 – deliver the session.**

---

*Last updated: 2026-06-15*
