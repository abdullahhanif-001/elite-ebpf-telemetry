#!/usr/bin/env bash
# run-scx-1202-evidence.sh — Phase 1 proof capture for SCX#1202 (fail-closed).
set -euo pipefail
export REAL_ONLY=1
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
EVID="${ELITE_SRC}/docs/evidence/scx-1202/VERIFICATION_${STAMP}"
mkdir -p "${EVID}"
FAIL=0

log() { echo "[scx1202-evidence] $*"; }

{
  echo "=== HOST FINGERPRINT ==="
  hostname
  uname -a
  grep -E 'CONFIG_SCHED_CLASS_EXT|CONFIG_FUNCTION_TRACER' "/boot/config-$(uname -r)" 2>/dev/null || true
  if command -v scx_loader >/dev/null 2>&1; then
    echo "scx_loader=$(command -v scx_loader)"
  else
    echo "scx_loader=not_in_path"
  fi
  cat /sys/kernel/debug/sched_ext/current 2>/dev/null | head -5 \
    || cat /sys/kernel/debug/sched/ext/current 2>/dev/null | head -5 \
    || echo 'sched_ext=unknown'
} | tee "${EVID}/00-preflight.txt"

if grep -q 'CONFIG_SCHED_CLASS_EXT=y' "${EVID}/00-preflight.txt" && grep -q 'scx_loader=not_in_path' "${EVID}/00-preflight.txt"; then
  log "FAIL: sched_ext kernel but scx_loader missing — build via scripts/server/sched-ext-vps-prep.sh scx-loader-build"
  exit 1
fi

log "[1/4] rt-guard-pass"
if bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-pass.sh" 2>&1 | tee "${EVID}/01-rt-guard-pass.log"; then
  :
else
  FAIL=$((FAIL + 1))
fi
LATEST_RT="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-* 2>/dev/null | head -1 || true)"
if [[ -f "${LATEST_RT}/verdict.txt" ]]; then
  cp "${LATEST_RT}/verdict.txt" "${EVID}/01-RT_GUARD_PASS.verdict"
fi
if ! grep -q 'RT_GUARD_PASS fail=0' "${EVID}/01-RT_GUARD_PASS.verdict" 2>/dev/null; then
  log "FAIL: RT_GUARD verdict missing or not PASS"
  FAIL=$((FAIL + 1))
fi

log "[2/4] scx1202-matrix-verify"
if bash "${ELITE_SRC}/benchmarks/ebpf-gates/scx1202-matrix-verify.sh" 2>&1 | tee "${EVID}/02-scx1202-matrix.log"; then
  grep 'SCX1202_MATRIX_PASS=YES' "${EVID}/02-scx1202-matrix.log" | tee "${EVID}/02-SCX1202_MATRIX.verdict"
else
  FAIL=$((FAIL + 1))
  grep 'SCX1202_MATRIX' "${EVID}/02-scx1202-matrix.log" | tee "${EVID}/02-SCX1202_MATRIX.verdict" || true
fi

log "[3/4] global-ebpf-aggregate"
if bash "${ELITE_SRC}/benchmarks/ebpf-gates/global-ebpf-aggregate.sh" 2>&1 | tee "${EVID}/03-global-aggregate.log"; then
  grep -E 'GLOBAL_EBPF|fail=0|GLOBAL result=PASS' "${EVID}/03-global-aggregate.log" | tee "${EVID}/03-GLOBAL.verdict"
else
  FAIL=$((FAIL + 1))
fi

log "[4/4] flood-safe + aggregate"
if bash "${ELITE_SRC}/benchmarks/sched-ext-gates/flood-safe-gate.sh" 2>&1 | tee "${EVID}/04-flood-safe.log"; then
  LATEST_FLOOD="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)"
  if [[ -n "${LATEST_FLOOD}" ]] && [[ -f "${LATEST_FLOOD}/checkpoint.json" ]]; then
    bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-flood-aggregate.sh" "${LATEST_FLOOD}" 2>&1 | tee -a "${EVID}/04-flood-safe.log"
    if [[ -f "${LATEST_FLOOD}/verdict.txt" ]]; then
      cp "${LATEST_FLOOD}/verdict.txt" "${EVID}/04-FLOOD.verdict"
    fi
  fi
  if [[ ! -f "${EVID}/04-FLOOD.verdict" ]]; then
    grep -E 'RT_GUARD_FLOOD_PASS fail=0|FLOOD_SAFE_GATE_PASS' "${EVID}/04-flood-safe.log" | tee "${EVID}/04-FLOOD.verdict" || true
  fi
else
  FAIL=$((FAIL + 1))
fi
if ! grep -qE 'RT_GUARD_FLOOD_PASS fail=0|FLOOD_SAFE_GATE_PASS' "${EVID}/04-FLOOD.verdict" 2>/dev/null; then
  log "FAIL: flood verdict missing or not PASS"
  FAIL=$((FAIL + 1))
fi

COMMIT_SHA="$(cd "${ELITE_SRC}" && git rev-parse HEAD 2>/dev/null || echo unknown)"
STATUS="FULL"
[[ "${FAIL}" -gt 0 ]] && STATUS="PARTIAL"

cat > "${EVID}/MANIFEST.json" <<EOF
{
  "verification_stamp": "${STAMP}",
  "commit_sha": "${COMMIT_SHA}",
  "kernel": "$(uname -r)",
  "host_class": "production server 4vCPU sched_ext",
  "real_only": 1,
  "status": "${STATUS}",
  "fail_count": ${FAIL},
  "gates": ["rt-guard-pass", "scx1202-matrix-verify", "global-ebpf-aggregate", "flood-safe-gate"]
}
EOF

log "EVIDENCE_DIR=${EVID} status=${STATUS} fail=${FAIL}"
for f in "${EVID}"/*.verdict; do
  [[ -f "$f" ]] && log "$(basename "$f"): $(cat "$f")"
done

if [[ "${FAIL}" -gt 0 ]]; then
  log "SCX1202_EVIDENCE_CAPTURE=FAIL"
  exit 1
fi

log "SCX1202_EVIDENCE_CAPTURE=PASS"
exit 0
