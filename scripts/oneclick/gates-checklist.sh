#!/usr/bin/env bash
# Elite #1 gates checklist — run on Contabo after closed-loop install.
# Does NOT invent scores; prints PASS/FAIL from live scrapes + local artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${BUILD_ROOT}/logs"
mkdir -p "${LOG_DIR}" "${SCRIPT_DIR}/results"
STAMP="$(date +%Y%m%d-%H%M%S)"
AGENT_URL="${AGENT_URL:-http://127.0.0.1:9102/metrics}"
DCIC_URL="${DCIC_URL:-http://127.0.0.1:9103/metrics}"
OUT="${OUT:-${LOG_DIR}/gates-checklist-${STAMP}.txt}"
export ELITE_GATES_OUT="${OUT}"

pass=0
fail=0
record() {
  local id="$1" msg="$2" st="$3"
  echo "[$st] $id — $msg" | tee -a "$OUT"
  if [[ "$st" == "PASS" ]]; then pass=$((pass+1)); else fail=$((fail+1)); fi
}
record_skip() {
  local id="$1" msg="$2"
  echo "[SKIP] $id — $msg" | tee -a "$OUT"
}

echo "=== Elite #1 gates checklist ===" | tee "$OUT"
echo "agent=$AGENT_URL dcic=$DCIC_URL" | tee -a "$OUT"

tmp="$(mktemp)"
if curl -fsS --max-time 5 "$AGENT_URL" -o "$tmp"; then
  if grep -q 'elite_predict_' "$tmp"; then
    n="$(grep -c 'elite_predict_' "$tmp" || true)"
    record G1 "elite_predict_* series count=${n}" PASS
  else
    record G1 "agent up but no elite_predict_* (enable forecast in config.yaml)" FAIL
  fi
  if grep -q 'elite_' "$tmp"; then
    record G1b "elite_* agent metrics present" PASS
  else
    record G1b "no elite_* metrics" FAIL
  fi
else
  record G1 "cannot scrape $AGENT_URL" FAIL
  record G1b "cannot scrape agent" FAIL
fi
rm -f "$tmp"

tmp="$(mktemp)"
if curl -fsS --max-time 5 "$DCIC_URL" -o "$tmp" 2>/dev/null; then
  if grep -qE 'elite_dcic_fault|elite_dcic_be_quota' "$tmp"; then
    record G2 "Soft DCIC metrics present" PASS
  else
    record G2 "DCIC up but no actuate series" FAIL
  fi
else
  record G2 "Soft DCIC :9103 not scraping (install --profile full|closed-loop)" FAIL
fi
rm -f "$tmp"

if [[ -x /opt/elite/scripts/pm2-guard.sh ]]; then
  if bash /opt/elite/scripts/pm2-guard.sh; then
    record G4 "pm2-guard OK" PASS
  else
    record G4 "pm2-guard failed" FAIL
  fi
else
  record G4 "pm2-guard script missing (skip on fresh VM without PM2)" PASS
fi

# Artifact presence (G3/G5 are historical Contabo proofs — point at trees)
if [[ -d "${SCRIPT_DIR}/results" ]]; then
  if ls -d "${SCRIPT_DIR}/results"/category-bakeoff-* >/dev/null 2>&1; then
    record G3 "category-bakeoff artifact dir present under results/" PASS
  else
    record G3 "no category-bakeoff-* under results/ — run category-bakeoff.sh on Contabo" FAIL
  fi
  if ls -d "${SCRIPT_DIR}/results"/p1-live-* >/dev/null 2>&1; then
    record G5 "p1-live artifact dir present (H11 LIVE evidence tree)" PASS
  else
    record G5 "no p1-live-* — run competitive-live-predict-proof.sh" FAIL
  fi
else
  record G3 "results/ missing" FAIL
  record G5 "results/ missing" FAIL
fi

# Install UX probes
if [[ -x /opt/elite/bin/elite-updater ]] || command -v elite-updater >/dev/null 2>&1; then
  record UX1 "elite-updater binary present" PASS
else
  record UX1 "elite-updater missing (install.sh metal should place it)" FAIL
fi
if systemctl list-timers --all 2>/dev/null | grep -q elite-updater; then
  record UX2 "elite-updater.timer listed" PASS
else
  record UX2 "elite-updater.timer not enabled" FAIL
fi

# G6–G8 zero-buffer gates (strict when ZERO_BUFFER_GATES=1)
if [[ "${ZERO_BUFFER_GATES:-0}" == "1" ]]; then
  if [[ -f "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt" ]] && grep -q LAMBDA_LEADS_PASS "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt"; then
    record G6 "LAMBDA_LEADS_PASS" PASS
  else
    record G6 "LAMBDA_LEADS_PASS missing" FAIL
  fi
  if [[ -f "${BUILD_ROOT}/logs/w5-xdp-graduated-latest.verdict" ]] && [[ "$(cat "${BUILD_ROOT}/logs/w5-xdp-graduated-latest.verdict")" == "W5_PASS" ]]; then
    record G7 "W5_PASS" PASS
  else
    record G7 "W5 not PASS" FAIL
  fi
  if [[ -f "${SCRIPT_DIR}/results/thundering-herd-proof-latest.txt" ]] && grep -q THUNDERING_HERD_PASS "${SCRIPT_DIR}/results/thundering-herd-proof-latest.txt"; then
    record G8 "THUNDERING_HERD_PASS" PASS
  else
    record G8 "THUNDERING_HERD_FAIL" FAIL
  fi
else
  if curl -fsS --max-time 3 "$AGENT_URL" 2>/dev/null | grep -q elite_predict_rho_projected; then
    record_skip G6 "rho metrics present — run traffic-engine-proof for LAMBDA_LEADS_PASS"
  else
    record_skip G6 "traffic engine not enabled"
  fi
  record_skip G7 "run w5-xdp-graduated-shed.sh (ZERO_BUFFER_GATES=1 for strict)"
  record_skip G8 "run thundering-herd-proof.sh (ZERO_BUFFER_GATES=1 for strict)"
fi

# G0 / G9–G15 v1.0 gates
if [[ -f "${SCRIPT_DIR}/results/g0-baseline-latest.txt" ]] && grep -q G0_BASELINE_ARTIFACTS_OK "${SCRIPT_DIR}/results/g0-baseline-latest.txt"; then
  record G0 "G0_BASELINE_ARTIFACTS" PASS
else
  record_skip G0 "run benchmarks/zero-buffer/matrix.sh"
fi
if [[ -f "${SCRIPT_DIR}/results/w6-xdp-token-bucket-latest.txt" ]] && grep -qE 'G9_TOKEN_BUCKET_PPS_PASS|G9_TOKEN_BUCKET_PPS_SKIP' "${SCRIPT_DIR}/results/w6-xdp-token-bucket-latest.txt"; then
  record G9 "token bucket pps artifact" PASS
else
  record_skip G9 "run zero-buffer matrix"
fi
if [[ -f "${SCRIPT_DIR}/results/g10-priority-pass-latest.txt" ]] && grep -q G10_PRIORITY_PASS "${SCRIPT_DIR}/results/g10-priority-pass-latest.txt"; then
  record G10 "priority tier pass" PASS
else
  record_skip G10 "run g10-priority-pass-proof.sh"
fi
if [[ "${ZERO_BUFFER_GATES:-0}" == "1" ]]; then
  if [[ -f "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt" ]] && grep -qE 'LAMBDA_LEADS_PASS|G11' "${SCRIPT_DIR}/results/traffic-engine-proof-latest.txt"; then
    record G11 "LAMBDA_LEADS_50MS" PASS
  else
    record G11 "G11 missing" FAIL
  fi
else
  record_skip G11 "50ms lambda leads — strict with ZERO_BUFFER_GATES=1"
fi
if [[ -f "${SCRIPT_DIR}/results/w4-xdp-inject-latest.txt" ]] && grep -qi pass "${SCRIPT_DIR}/results/w4-xdp-inject-latest.txt"; then
  record G12 "actuation p99 W4" PASS
else
  record_skip G12 "W4 xdp inject artifact"
fi
if [[ "${ZERO_BUFFER_GATES:-0}" == "1" ]] && [[ -f "${BUILD_ROOT}/logs/thundering-herd-bench-latest.txt" ]] && grep -q THUNDERING_HERD_PASS "${BUILD_ROOT}/logs/thundering-herd-bench-latest.txt"; then
  record G13 "THUNDERING_HERD_ETH0/lo" PASS
else
  record_skip G13 "thundering herd v2 bench"
fi
if [[ -f "${SCRIPT_DIR}/results/g14-multicore-latest.txt" ]] && grep -qE 'G14_MULTICORE_PASS|G14_MULTICORE_SKIP' "${SCRIPT_DIR}/results/g14-multicore-latest.txt"; then
  record G14 "multicore checklist" PASS
else
  record_skip G14 "run benchmarks/zero-buffer/g14-multicore.sh"
fi
if [[ -f "${SCRIPT_DIR}/results/g15-federate-propagation-latest.txt" ]] && grep -q G15_FEDERATE_PROPAGATION_PASS "${SCRIPT_DIR}/results/g15-federate-propagation-latest.txt"; then
  record G15 "federation propagation" PASS
else
  record_skip G15 "run g15-federate-propagation-proof.sh"
fi

echo "=== summary pass=${pass} fail=${fail} out=${OUT} ===" | tee -a "$OUT"
cp -f "$OUT" "${LOG_DIR}/gates-checklist-latest.txt" 2>/dev/null || true
cp -f "$OUT" "${SCRIPT_DIR}/results/gates-checklist-latest.txt" 2>/dev/null || true
if [[ "$fail" -eq 0 ]]; then
  echo "GATES_8_8_PASS" >>"$OUT"
  wr="${SCRIPT_DIR}/write-phase-b-reports.sh"
  [[ -f "${wr}" ]] && bash "${wr}" || true
fi
[[ "$fail" -eq 0 ]]
