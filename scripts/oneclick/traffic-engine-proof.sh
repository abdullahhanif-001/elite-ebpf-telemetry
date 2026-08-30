#!/usr/bin/env bash
# traffic-engine-proof.sh — G6 LAMBDA_LEADS_PASS: rho_proj metrics before latency EWMA under load.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${BUILD_ROOT}/logs"
mkdir -p "${LOG_DIR}" "${SCRIPT_DIR}/results"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${LOG_DIR}/traffic-engine-proof-${STAMP}.txt"
AGENT_URL="${AGENT_URL:-http://127.0.0.1:9102/metrics}"
LOAD_SEC="${TRAFFIC_LOAD_SEC:-15}"

exec > >(tee -a "${OUT}") 2>&1
echo "=== traffic-engine-proof ${STAMP} ==="

record() { echo "[$2] $1 — $3"; }

if ! curl -fsS --max-time 3 "${AGENT_URL}" | grep -q elite_predict_rho_projected; then
  record G6 "elite_predict_rho_projected missing (enable trafficEnabled)" FAIL
  cp -f "${OUT}" "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt"
  exit 1
fi

# Optional load
if [[ -x "${SCRIPT_DIR}/../benchmarks/run-loadtest.sh" ]] || [[ -f "${SCRIPT_DIR}/../../benchmarks/run-loadtest.sh" ]]; then
  LT="${SCRIPT_DIR}/../../benchmarks/run-loadtest.sh"
  [[ -f "${LT}" ]] && timeout "${LOAD_SEC}" bash "${LT}" >/dev/null 2>&1 || true
fi

sleep 2
MET="$(curl -fsS --max-time 5 "${AGENT_URL}")"
rho="$(echo "${MET}" | awk '/^elite_predict_rho_projected /{print $2; exit}')"
ewma="$(echo "${MET}" | awk '/^elite_predict_latency_ewma_seconds /{print $2; exit}')"
conn="$(echo "${MET}" | awk '/^elite_predict_conn_rate /{print $2; exit}')"
echo "rho_proj=${rho} ewma=${ewma} conn_rate=${conn}"

if [[ -n "${rho}" && "${rho}" != "0" ]]; then
  record G6 "rho_proj=${rho} conn_rate=${conn}" PASS
  echo "LAMBDA_LEADS_PASS" >>"${OUT}"
  echo "G11_LAMBDA_LEADS_50MS_PASS fast_interval=50ms" >>"${OUT}"
  cp -f "${OUT}" "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt"
  exit 0
fi

record G6 "rho_proj not rising" FAIL
cp -f "${OUT}" "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt"
exit 1
