#!/bin/bash
# Wait until the worker is Ready, then record its installed memory.
set -euo pipefail

: "${KUBECONFIG_PATH:?}"
: "${NODE_NAME:?}"
: "${MEMORY_GB:?}"

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl wait --for=condition=Ready "node/${NODE_NAME}" --timeout=300s
kubectl label node "$NODE_NAME" "lab.home/memory-gb=${MEMORY_GB}" --overwrite
