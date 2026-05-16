#!/usr/bin/env bash
# Start port-forwards for Grafana and Prometheus (kind doesn't route NodePorts to macOS)
# Run once after setup.sh; re-run if port-forwards drop.

set -euo pipefail
export KUBECONFIG="${HOME}/.kube/config"

pkill -f "kubectl port-forward.*monitoring" 2>/dev/null || true
sleep 1

kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 </dev/null >/dev/null 2>&1 &
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 </dev/null >/dev/null 2>&1 &

sleep 2
echo "Grafana:    http://localhost:3000  (admin/admin)"
echo "Prometheus: http://localhost:9090"
