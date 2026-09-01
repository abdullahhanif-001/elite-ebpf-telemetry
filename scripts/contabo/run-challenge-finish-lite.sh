#!/usr/bin/env bash
# run-challenge-finish-lite.sh — finish partial challenge on small VPS (P5 lite + tier3/4).
set -euo pipefail
export REAL_ONLY=1
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
export FLOOD_LITE_MODE=1
export FLOOD_SAFE_MODE=1
export PATH="/usr/local/bin:/root/.cargo/bin:${PATH}"

EVID="${ELITE_SRC}/docs/evidence/scx-1202/CHALLENGE_PROOF_$(date -u +%Y%m%d)"
mkdir -p "${EVID}"/{tier1,tier2,tier3,tier4}

PREV="$(ls -td "${ELITE_SRC}"/docs/evidence/scx-1202/CHALLENGE_PROOF_* 2>/dev/null | head -1 || true)"
if [[ -n "${PREV}" && "${PREV}" != "${EVID}" && -f "${PREV}/tier1/01-RT_GUARD_PASS.verdict" ]]; then
  cp -a "${PREV}/tier1/." "${EVID}/tier1/"
  cp "${PREV}/00-preflight.txt" "${EVID}/" 2>/dev/null || true
elif [[ -f "${EVID}/tier1/01-RT_GUARD_PASS.verdict" ]]; then
  echo "tier1 already in ${EVID}"
else
  echo "WARN: no tier1 — run tier1 first (rt-guard-pass)"
fi

FLOOD_OUT="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)"
if [[ -z "${FLOOD_OUT}" ]]; then
  FLOOD_OUT="${ELITE_SRC}/scripts/oneclick/results/rt-guard-flood-safe-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${FLOOD_OUT}"
fi
export FLOOD_OUT

echo "=== Andrea proof (repro — full, not lite) ==="
bash "${ELITE_SRC}/benchmarks/sched-ext-gates/prove-scx1202-arighi.sh" 2>&1 | tee "${EVID}/tier2/00-arighi.log"
LATEST_ARIGHI="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/arighi-proof-* | head -1)"
cp "${LATEST_ARIGHI}/verdict.txt" "${EVID}/tier2/ANDREA_PROOF.verdict"
cp "${LATEST_ARIGHI}/ANDREA_PROOF_REPORT.md" "${EVID}/tier2/"

bash "${ELITE_SRC}/benchmarks/sched-ext-gates/flood-safe-recovery.sh" || true

# P1-P4 if missing from checkpoint
for phase in P1 P2 P3 P4; do
  st="$(python3 -c "
import json
try:
  d=json.load(open('${FLOOD_OUT}/checkpoint.json'))
  print(d.get('phases',{}).get('${phase}',{}).get('status','MISSING'))
except Exception:
  print('MISSING')
" 2>/dev/null || echo MISSING)"
  if [[ "${st}" != "PASS" ]]; then
    echo "flood ${phase} (missing)"
    bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh" "${phase}" 2>&1 | tee "${EVID}/tier2/flood-${phase}.log"
    sleep 10
  else
    echo "flood ${phase} already PASS — skip"
  fi
done

echo "=== flood P5 lite ==="
bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh" P5 2>&1 | tee "${EVID}/tier2/flood-P5.log"
bash "${ELITE_SRC}/benchmarks/sched-ext-gates/rt-guard-flood-aggregate.sh" "${FLOOD_OUT}" 2>&1 | tee "${EVID}/tier2/flood-aggregate.log"
cp "${FLOOD_OUT}/verdict.txt" "${EVID}/tier2/04-FLOOD.verdict"

echo "=== tier3 holy grail ==="
RT_DIR="$(ls -td "${ELITE_SRC}"/scripts/oneclick/results/rt-guard-202* 2>/dev/null | grep -v flood | grep -v baseline | head -1 || true)"
export FLOOD_LITE_MODE=1
bash "${ELITE_SRC}/benchmarks/ebpf-gates/holy-grail-verify.sh" "${FLOOD_OUT}" "${RT_DIR}" 2>&1 | tee "${EVID}/tier3/02-holy-grail.log"
grep HOLY_GRAIL "${EVID}/tier3/02-holy-grail.log" | tee "${EVID}/tier3/02-HOLY_GRAIL.verdict" || true
[[ -f "${FLOOD_OUT}/scheduler-matrix.json" ]] && cp "${FLOOD_OUT}/scheduler-matrix.json" "${EVID}/tier3/" || true

echo "=== tier4 global eBPF ==="
bash "${ELITE_SRC}/benchmarks/ebpf-gates/global-ebpf-inventory.sh" 2>&1 | tee "${EVID}/tier4/D1-inventory.log" || true
bash "${ELITE_SRC}/benchmarks/ebpf-gates/telemetry-probe-gate.sh" 2>&1 | tee "${EVID}/tier4/D3-telemetry.log" || true
bash "${ELITE_SRC}/scripts/oneclick/ebpf-xray-real-proof.sh" 2>&1 | tee "${EVID}/tier4/D4-xray.log" || true
bash "${ELITE_SRC}/benchmarks/ebpf-gates/ebpf-future-holes.sh" 2>&1 | tee "${EVID}/tier4/D6-future-holes.log" || true
bash "${ELITE_SRC}/benchmarks/ebpf-gates/global-ebpf-aggregate.sh" 2>&1 | tee "${EVID}/tier4/03-global-aggregate.log" || true
grep -E 'GLOBAL_EBPF|fail=0|GLOBAL result=PASS' "${EVID}/tier4/03-global-aggregate.log" | tee "${EVID}/tier4/03-GLOBAL.verdict" || true

{
  echo "=== CHALLENGE PROOF PREFLIGHT ==="
  date -u +%Y-%m-%dT%H:%MZ
  hostname
  uname -a
  echo "FLOOD_LITE_MODE=1"
  grep -E 'CONFIG_SCHED_CLASS_EXT' "/boot/config-$(uname -r)" 2>/dev/null || true
  command -v scx_loader 2>/dev/null || ls /usr/local/bin/scx_loader 2>/dev/null || true
} | tee "${EVID}/00-preflight.txt"

COMMIT_SHA="$(cd "${ELITE_SRC}" && git rev-parse HEAD 2>/dev/null || echo unknown)"
cat > "${EVID}/MANIFEST.json" <<EOF
{
  "challenge_stamp": "$(date -u +%Y%m%d)",
  "commit_sha": "${COMMIT_SHA}",
  "kernel": "$(uname -r)",
  "host_class": "Contabo VPS 4vCPU 8GB lite flood",
  "flood_lite_mode": 1,
  "real_only": 1,
  "tiers": ["T1-SCX-core", "T2-Andrea-flood-lite", "T3-Holy-Grail", "T4-Global-eBPF"]
}
EOF

FAIL=0
grep -q 'RT_GUARD_PASS fail=0' "${EVID}/tier1/01-RT_GUARD_PASS.verdict" 2>/dev/null || FAIL=$((FAIL+1))
grep -q 'ANDREA_PROOF_PASS fail=0' "${EVID}/tier2/ANDREA_PROOF.verdict" || FAIL=$((FAIL+1))
grep -q 'RT_GUARD_FLOOD_PASS fail=0' "${EVID}/tier2/04-FLOOD.verdict" || FAIL=$((FAIL+1))
grep -q 'HOLY_GRAIL_1202_SOLVED=YES' "${EVID}/tier3/02-HOLY_GRAIL.verdict" || FAIL=$((FAIL+1))
grep -qE 'fail=0|GLOBAL result=PASS' "${EVID}/tier4/03-GLOBAL.verdict" || FAIL=$((FAIL+1))

if [[ "${FAIL}" -eq 0 ]]; then
  echo "LINUX_EBPF_CHALLENGE_PASS fail=0 host=$(hostname) kernel=$(uname -r) mode=lite" | tee "${EVID}/CHALLENGE_VERDICT.txt"
else
  echo "LINUX_EBPF_CHALLENGE_FAIL fail=${FAIL} mode=lite" | tee "${EVID}/CHALLENGE_VERDICT.txt"
  exit 1
fi
echo "EVIDENCE_DIR=${EVID}"
