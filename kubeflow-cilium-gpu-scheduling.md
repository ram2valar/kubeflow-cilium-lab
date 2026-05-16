## Title

When Kubeflow Fights Cilium: Debugging 60% Idle GPUs in Kubernetes

---

## Description

We built a research testbed to validate ML workload scalability on Kubernetes with Kubeflow and Cilium. During 500-node stress tests, GPUs sat idle 60% of the time while pods waited for available resources.

Through controlled experiments, we isolated the cause: Kubeflow's pipeline scheduler and Cilium's network-aware pod placement make conflicting decisions. Kubeflow schedules pods without considering network topology. Cilium optimizes networking but can't move scheduled pods. Result? GPUs unused while the scheduler searches for placement that won't happen.

This talk shares our systematic investigation, diagnostic methodology, and scheduling constraints that resolved it. Lab tests show GPU utilization improved from 40% to 85%. You'll see the problem reproduced live, understand why it's hard to detect, and get tested Kubernetes configs. This matters for anyone planning distributed training with Kubeflow or similar orchestrators on network-optimized clusters.

---

## Track

**Primary**: AI + ML  
**Secondary**: Operations + Performance

---

## Level

Intermediate

---

## Benefits to the Ecosystem

**Preventive Knowledge Sharing**: Through systematic lab research, we identified integration conflicts between Kubeflow and Cilium before production deployment. This proactive discovery enables teams to avoid GPU scheduling issues entirely, preventing costly debugging in production environments.

**Reproducible Research Methodology**: Our controlled lab experiments provide a reproducible testing framework for validating ML orchestrator and CNI interactions. Teams can replicate our setup to test similar configurations before production use, reducing deployment risk.

**Fills Critical Documentation Gap**: Neither Kubeflow nor Cilium documentation addresses how these projects interact under heavy GPU scheduling load. Our research-backed findings fill this gap with empirical data from systematic testing at scale.

**Provides Diagnostic Framework**: We share specific debugging methodology, Prometheus queries, and symptom identification patterns developed through lab research. This troubleshooting approach applies to any scenario where scheduling and network placement systems interact.

**Delivers Lab-Validated Configurations**: Our Kubernetes pod topology spread constraints and node labeling strategies are tested across multiple scenarios (varying node counts, GPU ratios, workload patterns). Teams get solutions validated through scientific experimentation, not trial-and-error.

**Reduces Production Risk**: Organizations can apply our lab-tested patterns without expensive experimentation in production. We've done the systematic testing so others can deploy confidently with known-good configurations.

**Contributes Research Insights to Projects**: Academic perspective on CNCF project integration challenges helps improve default configurations, documentation, and potentially future development priorities for AI/ML use cases.

---

## CNCF-hosted Software

- Kubernetes (Graduated)
- Cilium (Graduated)
- Kubeflow (Incubating)
- Prometheus (Graduated)

---

## Open Source Projects

- Kubeflow Pipelines
- NVIDIA GPU Operator
- kube-scheduler plugins
- Kubernetes descheduler

---

## Additional Resources

**Research Methodology:**
- Experimental Setup Documentation: Details of our 500-node research testbed configuration, including hardware specs, network topology, and GPU allocation strategy
- Testing Methodology: Systematic approach to load testing, metrics collection, and controlled experimentation used to isolate the scheduling conflict
- Reproducibility Guide: Step-by-step instructions for replicating our experiments in other lab environments or validation clusters

**Primary Technical Resources:**
- Kubeflow Pipelines GitHub: https://github.com/kubeflow/pipelines
- Cilium Documentation: https://docs.cilium.io/
- Kubernetes Scheduler Concepts: https://kubernetes.io/docs/concepts/scheduling-eviction/
- Pod Topology Spread Constraints: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

**Background Reading:**
- Cilium Network Topology Awareness: https://docs.cilium.io/en/stable/network/concepts/routing/
- Kubeflow Pipeline Scheduling: https://www.kubeflow.org/docs/components/pipelines/overview/
- GPU Scheduling in Kubernetes: https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/
- Kubernetes Scheduler Performance Tuning: https://kubernetes.io/docs/concepts/scheduling-eviction/scheduler-perf-tuning/

**Research Context:**
This work originated from university research lab experiments focused on understanding production-readiness challenges of CNCF projects for AI/ML workloads at scale. Our academic approach emphasizes reproducibility, systematic testing, and preventive problem identification.

**Lab Infrastructure Details:**
- 500-node Kubernetes testbed for ML workload validation
- Mix of GPU-enabled nodes (NVIDIA A100, V100) for diverse testing scenarios
- Prometheus + Grafana stack for comprehensive observability
- Controlled network topology enabling Cilium eBPF testing

**Diagnostic Tools & Metrics:**
- Prometheus Query Examples: Specific PromQL queries we developed to identify GPU idle patterns and scheduling conflicts
- Grafana Dashboards: Pre-built dashboards for visualizing GPU utilization, pod scheduling latency, and Cilium network metrics
- kubectl Plugins: Custom tools for inspecting scheduler decisions and Cilium pod placement

**Community Resources:**
- Kubernetes SIG-Scheduling: https://github.com/kubernetes/community/tree/master/sig-scheduling
- Kubernetes SIG-Network: https://github.com/kubernetes/community/tree/master/sig-network
- CNCF AI/ML Working Group: Community discussions on AI workload challenges

**Deliverables (Post-Acceptance):**
- GitHub Repository: Complete lab setup scripts, Kubernetes manifests, and configuration files
- Research Paper: Detailed technical write-up of our methodology and findings (academic publication)
- Video Demos: Recorded demonstrations of the problem and solution for self-paced learning
- Community Office Hours: Post-talk Q&A sessions for teams implementing similar solutions

**Collaboration Opportunities:**
This research represents collaboration between industry practitioners and academic researchers. We welcome partnerships with other teams experiencing similar challenges or interested in validating findings in their environments.
