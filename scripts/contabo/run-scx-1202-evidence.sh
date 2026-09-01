#!/usr/bin/env bash
# run-scx-1202-evidence.sh — Phase 1 proof capture for SCX#1202 green signal.
set -euo pipefail
export REAL_ONLY=1
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
EVID="${ELITE_SRC}/docs/evidence/scx-1202/VERIFICATION_${STAMP}"
mkdir -p "${EVID}"

{
  echo "=== HOST FINGERPRINT ==="
  hostname
  uname -a
  grep -E 'CONFIG_SCHED_CLASS_EXT|CONFIG_FUNCTION_TRACER' "/boot/config-$(uname -r)" 2>/dev/null || true
  command -v scx_loader 2>/dev/null || find /opt/scx /usr/local/bin -name 'scx_loader' 2>/dev/null | head -1 || echo 'scx_loader=not_in_path'
  cat /sys/kernel/debug/sched/ext_server/status 2>/dev/null | head -5 || echo 'ext_server=unknown'
} | tee "${EVID}/00-preflight.txt"

echo "[1/4] rt-guard-pass"
bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-pass.sh" 2>&1 | tee "${EVID}/01-rt-guard-pass.log"
LATEST_RT="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-* 2>/dev/null | head -1)"
if [[ -f "${LATEST_RT}/verdict.txt" ]]; then
  cp "${LATEST_RT}/verdict.txt" "${EVID}/01-RT_GUARD_PASS.verdict"
fi

echo "[2/4] holy-grail-verify"
bash "${ELITE_SRC}/benchmarks/ebpf-gates/holy-grail-verify.sh" 2>&1 | tee "${EVID}/02-holy-grail.log"
grep HOLY_GRAIL "${EVID}/02-holy-grail.log" | tee "${EVID}/02-HOLY_GRAIL.verdict" || true

echo "[3/4] global-ebpf-aggregate"
bash "${ELITE_SRC}/benchmarks/ebpf-gates/global-ebpf-aggregate.sh" 2>&1 | tee "${EVID}/03-global-aggregate.log"
grep -E 'GLOBAL_EBPF|fail=0|GLOBAL result=PASS' "${EVID}/03-global-aggregate.log" | tee "${EVID}/03-GLOBAL.verdict" || true

echo "[4/4] flood-safe + aggregate"
bash "${ELITE_SRC}/benchmarks/sched-ext-gates/flood-safe-gate.sh" 2>&1 | tee "${EVID}/04-flood-safe.log"
LATEST_FLOOD="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)"
if [[ -n "${LATEST_FLOOD}" ]] && [[ -f "${LATEST_FLOOD}/checkpoint.json" ]]; then
  bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-flood-aggregate.sh" "${LATEST_FLOOD}" 2>&1 | tee -a "${EVID}/04-flood-safe.log" || true
  if [[ -f "${LATEST_FLOOD}/verdict.txt" ]]; then
    cp "${LATEST_FLOOD}/verdict.txt" "${EVID}/04-FLOOD.verdict"
  fi
fi
if [[ ! -f "${EVID}/04-FLOOD.verdict" ]]; then
  grep -E 'RT_GUARD_FLOOD_PASS|FLOOD_SAFE_GATE_PASS' "${EVID}/04-flood-safe.log" | tee "${EVID}/04-FLOOD.verdict" || true
fi

COMMIT_SHA="$(cd "${ELITE_SRC}" && git rev-parse HEAD 2>/dev/null || echo unknown)"
cat > "${EVID}/MANIFEST.json" <<EOF
{
  "verification_stamp": "${STAMP}",
  "commit_sha": "${COMMIT_SHA}",
  "kernel": "$(uname -r)",
  "host_class": "Contabo VPS 4vCPU sched_ext",
  "real_only": 1,
  "gates": ["rt-guard-pass", "holy-grail-verify", "global-ebpf-aggregate", "flood-safe-gate"]
}
EOF

echo "EVIDENCE_DIR=${EVID}"
echo "=== VERDICTS ==="
for f in "${EVID}"/*.verdict; do
  [[ -f "$f" ]] && echo "$(basename "$f"): $(cat "$f")"
done
