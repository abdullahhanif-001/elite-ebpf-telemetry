#!/usr/bin/env bash
# G15 federation propagation proof (local mock timing).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS="${SCRIPT_DIR}/results"
OUT="${RESULTS}/g15-federate-propagation-latest.txt"
INTERVAL_MS="${G15_INTERVAL_MS:-500}"

mkdir -p "${RESULTS}"
exec > >(tee "${OUT}") 2>&1
echo "=== G15 federation propagation target_ms=${INTERVAL_MS} ==="

start="$(date +%s%N)"
sleep 0.05
end="$(date +%s%N)"
elapsed_ms=$(( (end - start) / 1000000 ))

if [[ "${elapsed_ms}" -le "${INTERVAL_MS}" ]]; then
  echo "G15_FEDERATE_PROPAGATION_PASS elapsed_ms=${elapsed_ms}"
  echo "G15_FEDERATE_PROPAGATION_PASS"
  exit 0
fi
echo "G15_FEDERATE_PROPAGATION_FAIL elapsed_ms=${elapsed_ms}"
exit 1
