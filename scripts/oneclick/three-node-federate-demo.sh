#!/usr/bin/env bash
# three-node-federate-demo.sh — documents 3-node federation (run elite-controller + agents).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${ELITE_BUILD_ROOT:-/opt/elite-build}/logs/three-node-federate-${STAMP:-demo}.txt"
mkdir -p "$(dirname "${OUT}")"

{
  echo "=== three-node federate demo ==="
  echo "Start elite-controller:"
  echo "  ELITE_CONTROLLER_NODES=http://node1:9102/metrics,http://node2:9102/metrics go run ${REPO_ROOT}/cmd/elite-controller"
  echo "Query: curl -s http://127.0.0.1:9200/policy"
  echo "Each node: elite-agent with trafficEnabled + policyMapPin"
  echo "Federated max_rho drives regional shed_ppm caps (manual or controller pull)"
  echo "THREE_NODE_FEDERATE_DOC_OK"
} | tee "${OUT}"
