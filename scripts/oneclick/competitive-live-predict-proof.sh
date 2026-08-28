#!/usr/bin/env bash
# H11 — Live predict inject proof: MOCK_ → elite_predict / decision bus → Soft DCIC signal.
# Exit 0 PASS, 2 SKIP (components not installed), 1 FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)"
OUT_DIR="${ELITE_LIVE_PREDICT_OUT:-/tmp/elite-live-predict-${STAMP}}"
DECISION="${ELITE_DECISION_PATH:-/var/lib/elite/predict-decision.json}"
DCIC_METRICS="${ELITE_DCIC_METRICS:-127.0.0.1:9103/metrics}"
PREDICT_METRICS="${ELITE_PREDICT_METRICS:-127.0.0.1:9102/metrics}"
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
  return 2
}

fetch() {
  local target="$1" out="$2"
  # host:port/path — python adds scheme to avoid shell S5332 noise in comments elsewhere
  python3 - "$target" "$out" <<'PY'
import sys, urllib.request
target, out = sys.argv[1], sys.argv[2]
url = target if "://" in target else "http://" + target
try:
    with urllib.request.urlopen(url, timeout=3) as r:
        open(out, "w", encoding="utf-8").write(r.read().decode("utf-8", "replace"))
    sys.exit(0)
except Exception as e:
    open(out, "w", encoding="utf-8").write("ERROR " + str(e))
    sys.exit(1)
PY
}

echo "=== LIVE PREDICT H11 ${STAMP} ==="

set +e
pm2_guard >"${OUT_DIR}/pm2-before.txt" 2>&1
set -e
if grep -q PM2_GUARD_OK "${OUT_DIR}/pm2-before.txt" 2>/dev/null; then
  record L0 "PM2 before" PASS
else
  record L0 "PM2 before" SKIP
fi

# Baseline DCIC / predict
set +e
fetch "${DCIC_METRICS}" "${OUT_DIR}/dcic-before.txt"
d_before=$?
fetch "${PREDICT_METRICS}" "${OUT_DIR}/predict-before.txt"
p_before=$?
set -e

if [[ "${d_before}" -ne 0 && "${p_before}" -ne 0 ]]; then
  record L1 "neither Soft DCIC nor agent metrics up" SKIP
  # Still run pure MOCK_ decision-bus shape (unit-level) so suite has a signal
  bash "${SCRIPT_DIR}/mock-inject-proof.sh" | tee "${OUT_DIR}/mock.txt"
  record L2 "MOCK_ decision bus shape only" PASS
  echo "H11_SKIP_NO_RUNTIME" >"${OUT_DIR}/verdict.txt"
  exit 2
fi

if [[ "${d_before}" -eq 0 ]]; then
  record L1a "Soft DCIC metrics reachable" PASS
  awk '/^elite_dcic_be_quota_percent|^elite_dcic_noise_score|^elite_dcic_fault/{print}' \
    "${OUT_DIR}/dcic-before.txt" >"${OUT_DIR}/dcic-before-keys.txt" || true
else
  record L1a "Soft DCIC not up — predict-only path" SKIP
fi

# MOCK_ inject — skipped when REAL_ONLY=1 (live scrape only)
if [[ "${REAL_ONLY:-0}" == "1" ]]; then
  record L2 "REAL_ONLY: skip MOCK decision inject" PASS
  set +e
  fetch "${DCIC_METRICS}" "${OUT_DIR}/dcic-after.txt"
  d_after=$?
  fetch "${PREDICT_METRICS}" "${OUT_DIR}/predict-after.txt"
  p_after=$?
  set -e
else
  mkdir -p "$(dirname "${DECISION}")"
  cat >"${DECISION}" <<'EOF'
{"fault":true,"cause":"network","projected":0.25,"ewma":0.18,"updated_at":"2026-08-24T00:00:00Z","mode":"semi"}
EOF
  record L2 "wrote MOCK_ decision bus ${DECISION}" PASS
  python3 - <<PY
import json
d=json.load(open("${DECISION}"))
assert d["fault"] is True
assert d["cause"] in ("network","llc","psi","mixed")
print("MOCK_ decision OK", d["cause"])
PY
  sleep 3
  set +e
  fetch "${DCIC_METRICS}" "${OUT_DIR}/dcic-after.txt"
  d_after=$?
  fetch "${PREDICT_METRICS}" "${OUT_DIR}/predict-after.txt"
  p_after=$?
  set -e
fi

ACTUATED=0
if [[ "${d_after}" -eq 0 ]]; then
  if grep -qE '^elite_dcic_' "${OUT_DIR}/dcic-after.txt"; then
    record L3 "Soft DCIC metrics still healthy after inject" PASS
    ACTUATED=1
  else
    record L3 "Soft DCIC metrics empty after inject" FAIL
  fi
  # Prefer seeing fault or quota series present (actuate path available)
  if grep -qE '^elite_dcic_fault|^elite_dcic_be_quota_percent' "${OUT_DIR}/dcic-after.txt"; then
    record L4 "actuate-relevant DCIC series present" PASS
  else
    record L4 "DCIC series missing fault/quota (observe-only mode OK)" SKIP
  fi
else
  record L3 "DCIC still down after inject" SKIP
fi

# Predict metrics: live elite_predict_* required for H11_PASS_LIVE
LIVE_PREDICT=0
if [[ "${p_after}" -eq 0 ]] && grep -q 'elite_predict_' "${OUT_DIR}/predict-after.txt"; then
  record L5 "elite_predict_* present on agent" PASS
  LIVE_PREDICT=1
elif [[ "${p_after}" -eq 0 ]]; then
  record L5 "agent up but no elite_predict_* (forecast may be disabled)" SKIP
else
  record L5 "agent metrics unreachable" SKIP
fi

set +e
pm2_guard >"${OUT_DIR}/pm2-after.txt" 2>&1
set -e
if grep -q PM2_GUARD_OK "${OUT_DIR}/pm2-after.txt" 2>/dev/null; then
  record L6 "PM2 after" PASS
else
  record L6 "PM2 after" SKIP
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "H11_FAIL" >"${OUT_DIR}/verdict.txt"
  exit 1
fi

# Honesty: MOCK bus alone is never live PASS (ADR-005 / Track C).
if [[ "${LIVE_PREDICT}" -eq 1 ]]; then
  echo "H11_PASS_LIVE" >"${OUT_DIR}/verdict.txt"
  mkdir -p "${SCRIPT_DIR}/results"
  cp -a "${OUT_DIR}/results.txt" "${SCRIPT_DIR}/results/live-predict-${STAMP}.txt" 2>/dev/null || true
  echo "=== H11 LIVE OK ==="
  exit 0
fi
if [[ "${ACTUATED}" -eq 1 ]]; then
  echo "H11_PASS_DCIC_ONLY" >"${OUT_DIR}/verdict.txt"
  record L7 "DCIC up but no elite_predict_* — not full live" SKIP
  echo "=== H11 SKIP (DCIC without predict metrics) ==="
  exit 2
fi
echo "H11_PASS_BUS" >"${OUT_DIR}/verdict.txt"
record L7 "MOCK bus only — not live predict PASS" SKIP
mkdir -p "${SCRIPT_DIR}/results"
cp -a "${OUT_DIR}/results.txt" "${SCRIPT_DIR}/results/live-predict-${STAMP}.txt" 2>/dev/null || true
echo "=== H11 SKIP (bus-only; not live) ==="
exit 2
