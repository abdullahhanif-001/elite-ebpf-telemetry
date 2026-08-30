#!/usr/bin/env bash
# thundering-herd-proof.sh — G8 THUNDERING_HERD_PASS synthetic spike RSS cap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${BUILD_ROOT}/logs"
mkdir -p "${LOG_DIR}" "${SCRIPT_DIR}/results"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${LOG_DIR}/thundering-herd-${STAMP}.txt"
BENCH="${REPO_ROOT}/benchmarks/thundering-herd/run.sh"

exec > >(tee -a "${OUT}") 2>&1
echo "=== thundering-herd-proof ${STAMP} ==="

if [[ -x "${BENCH}" ]]; then
  bash "${BENCH}" || true
fi

if grep -q THUNDERING_HERD_PASS "${LOG_DIR}/thundering-herd-bench-latest.txt" 2>/dev/null; then
  echo "THUNDERING_HERD_PASS" >>"${OUT}"
  cp -f "${OUT}" "${SCRIPT_DIR}/results/thundering-herd-proof-latest.txt"
  exit 0
fi

# Fallback: agent RSS scrape under load
AGENT_PID="$(pgrep -f elite-agent 2>/dev/null | head -1 || true)"
if [[ -n "${AGENT_PID}" ]]; then
  rss="$(awk '/^VmRSS:/ {print $2}' "/proc/${AGENT_PID}/status" 2>/dev/null || echo 0)"
  echo "elite-agent RSS kB=${rss}"
  if [[ "${rss}" -lt 262144 ]]; then
    echo "THUNDERING_HERD_PASS" >>"${OUT}"
    cp -f "${OUT}" "${SCRIPT_DIR}/results/thundering-herd-proof-latest.txt"
    exit 0
  fi
fi

echo "THUNDERING_HERD_FAIL" >>"${OUT}"
cp -f "${OUT}" "${SCRIPT_DIR}/results/thundering-herd-proof-latest.txt"
exit 1
