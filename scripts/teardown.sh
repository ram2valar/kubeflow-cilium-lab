#!/usr/bin/env bash
# Tear down the entire lab
set -euo pipefail
echo "Deleting kind cluster 'kubeflow-cilium-demo'..."
kind delete cluster --name kubeflow-cilium-demo
echo "Done."
