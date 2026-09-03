#!/usr/bin/env bash
# rt-guard-flood-aggregate.sh — merge safe flood checkpoints into verdict + report.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

GATES_DIR="$(script_dir)"
ROOT="$(repo_root)"
FLOOD_DIR="${1:-$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true)}"

[[ -d "${FLOOD_DIR}" ]] || { echo "FAIL: no flood dir ${FLOOD_DIR}" >&2; exit 1; }

FAIL=0
for phase in P1 P2 P3 P4 P5; do
  st="$(python3 -c "
import json,sys
try:
  d=json.load(open('${FLOOD_DIR}/checkpoint.json'))
  print(d.get('phases',{}).get('${phase}',{}).get('status','MISSING'))
except Exception:
  print('MISSING')
")"
  echo "phase ${phase}=${st}"
  [[ "${st}" == "PASS" ]] || FAIL=$((FAIL + 1))
done

bash "${GATES_DIR}/generate-evidence-report.sh" "${FLOOD_DIR}" || true

# Patch report header for safe mode
if [[ -f "${FLOOD_DIR}/EVIDENCE_REPORT.md" ]]; then
  sed -i 's/REAL_ONLY:\*\* 1/REAL_ONLY:** 1  mode: safe_4vcpu/' "${FLOOD_DIR}/EVIDENCE_REPORT.md" 2>/dev/null || true
fi

KERNEL="$(uname -r 2>/dev/null || echo unknown)"
HOST="$(hostname 2>/dev/null || echo unknown)"
if [[ "${FAIL}" -eq 0 ]]; then
  echo "RT_GUARD_FLOOD_PASS fail=0 mode=safe_4vcpu host=${HOST} kernel=${KERNEL}" | tee "${FLOOD_DIR}/verdict.txt"
  cp "${FLOOD_DIR}/EVIDENCE_REPORT.md" "${ROOT}/contrib/sched-ext/EVIDENCE_REPORT.md" 2>/dev/null || true
  bash "${ROOT}/benchmarks/ebpf-gates/scx1202-matrix-verify.sh" "${FLOOD_DIR}" 2>/dev/null || true
  echo "AGGREGATE_OK out=${FLOOD_DIR}"
else
  echo "RT_GUARD_FLOOD_FAIL fail=${FAIL} mode=safe_4vcpu host=${HOST}" | tee "${FLOOD_DIR}/verdict.txt"
  exit 1
fi
