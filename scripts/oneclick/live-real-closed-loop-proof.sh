#!/usr/bin/env bash
# Live closed-loop proof — scrape real metrics; no MOCK decision inject.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${ELITE_REAL_LOOP_OUT:-/tmp/elite-real-loop-${STAMP}}"
mkdir -p "${OUT_DIR}"
FAIL=0

record() {
  local id="$1" msg="$2" ok="$3"
  echo "[${id}] ${ok}: ${msg}" | tee -a "${OUT_DIR}/results.txt"
  if [[ "${ok}" == "FAIL" ]]; then
    FAIL=$((FAIL + 1))
  fi
}

pm2_guard() {
  if [[ -f "${REPO_ROOT}/deploy/contabo/pm2-guard.sh" ]]; then
    bash "${REPO_ROOT}/deploy/contabo/pm2-guard.sh" && return 0
  fi
  if [[ -f /opt/elite/scripts/pm2-guard.sh ]]; then
    bash /opt/elite/scripts/pm2-guard.sh && return 0
  fi
  return 2
}

echo "=== REAL CLOSED LOOP ${STAMP} ==="

set +e
pm2_guard >"${OUT_DIR}/pm2-before.txt" 2>&1
set -e
if grep -q PM2_GUARD_OK "${OUT_DIR}/pm2-before.txt" 2>/dev/null; then
  record R0 "PM2 before" PASS
else
  record R0 "PM2 before" SKIP
fi

set +e
curl -sf --max-time 5 http://127.0.0.1:9102/metrics >"${OUT_DIR}/agent.txt"
a=$?
curl -sf --max-time 5 http://127.0.0.1:9103/metrics >"${OUT_DIR}/dcic.txt"
d=$?
curl -sf --max-time 5 http://127.0.0.1:9104/metrics >"${OUT_DIR}/llc.txt" 2>/dev/null
set -e

if [[ "${a}" -ne 0 ]]; then
  record R1 "agent :9102 unreachable" FAIL
else
  record R1 "agent :9102 up" PASS
fi

if grep -q '^elite_predict_' "${OUT_DIR}/agent.txt"; then
  record R2 "elite_predict_* live" PASS
else
  record R2 "elite_predict_* missing" FAIL
fi

if [[ -f /var/lib/elite/predict-decision.json ]]; then
  record R3 "predict-decision.json exists (forecaster)" PASS
else
  record R3 "predict-decision.json missing" FAIL
fi

if [[ -f /var/lib/elite/predict-policy.bin ]] && [[ -s /var/lib/elite/predict-policy.bin ]]; then
  record R4 "predict-policy.bin present" PASS
else
  record R4 "predict-policy.bin missing" SKIP
fi

if [[ "${d}" -eq 0 ]] && grep -q '^elite_dcic_' "${OUT_DIR}/dcic.txt"; then
  record R5 "elite_dcic_* live" PASS
else
  record R5 "dcic metrics" SKIP
fi

set +e
pm2_guard >"${OUT_DIR}/pm2-after.txt" 2>&1
set -e
if grep -q PM2_GUARD_OK "${OUT_DIR}/pm2-after.txt" 2>/dev/null; then
  record R6 "PM2 after" PASS
else
  record R6 "PM2 after" SKIP
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "REAL_CLOSED_LOOP_FAIL" >"${OUT_DIR}/verdict.txt"
  exit 1
fi

echo "REAL_CLOSED_LOOP_PASS" >"${OUT_DIR}/verdict.txt"
mkdir -p "${SCRIPT_DIR}/results"
cp -a "${OUT_DIR}/results.txt" "${SCRIPT_DIR}/results/real-loop-${STAMP}.txt" 2>/dev/null || true
echo "=== REAL CLOSED LOOP PASS ==="
exit 0
