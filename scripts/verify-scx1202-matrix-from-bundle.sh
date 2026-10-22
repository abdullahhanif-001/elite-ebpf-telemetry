#!/usr/bin/env bash
# verify-scx1202-matrix-from-bundle.sh — re-validate H1–H12 from committed FULL evidence
# (no sched_ext kernel required). Complements live scx1202-matrix-verify.sh on VPS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID_BASE="${ROOT}/docs/evidence/scx-1202"

mapfile -t _bundles < <(find "${EVID_BASE}" -maxdepth 1 -type d -name 'VERIFICATION_*' | sort -r)
bundle=""
for _b in "${_bundles[@]}"; do
  if grep -qE '"status"[[:space:]]*:[[:space:]]*"FULL"' "${_b}/MANIFEST.json" 2>/dev/null; then
    bundle="${_b}"
    break
  fi
done
[[ -n "${bundle}" ]] || { echo "FAIL: no FULL VERIFICATION_* bundle" >&2; exit 1; }

FAIL=0
need() {
  local label="$1" file="$2" pattern="$3"
  if [[ ! -f "${file}" ]]; then
    echo "FAIL ${label}: missing ${file}" >&2
    FAIL=$((FAIL + 1))
    return
  fi
  if ! grep -qE "${pattern}" "${file}"; then
    echo "FAIL ${label}: pattern not in ${file}" >&2
    FAIL=$((FAIL + 1))
  else
    echo "OK   ${label}"
  fi
}

echo "Bundle: ${bundle}"

matrix_verdict=""
for cand in "${bundle}/02-SCX1202_MATRIX.verdict" "${bundle}/02-HOLY_GRAIL.verdict"; do
  [[ -f "${cand}" ]] && matrix_verdict="${cand}" && break
done

need "matrix verdict" "${matrix_verdict}" 'SCX1202_MATRIX_PASS=YES.*checks=12/12'
need "matrix log" "${bundle}/02-scx1202-matrix.log" 'SCX1202_MATRIX_PASS=YES'

pass_count="$(grep -cE '^  H[0-9]+: PASS' "${bundle}/02-scx1202-matrix.log" 2>/dev/null || true)"
pass_count="${pass_count:-0}"
if [[ "${pass_count}" -lt 12 ]]; then
  echo "FAIL matrix log: expected 12 Hn: PASS lines, got ${pass_count}" >&2
  FAIL=$((FAIL + 1))
else
  echo "OK   matrix log H1–H12 PASS lines (${pass_count})"
fi

need "rt-guard log STALL" "${bundle}/01-rt-guard-pass.log" 'STALL_DETECTED=NO'
need "rt-guard log loader" "${bundle}/01-rt-guard-pass.log" 'LOADER=bpfland'
need "rt-guard log soak" "${bundle}/01-rt-guard-pass.log" '60s soak with RT\+EXT'
need "rt-guard log EXT%" "${bundle}/01-rt-guard-pass.log" 'EXT task got [4-9]\.'
need "rt-guard verdict" "${bundle}/01-RT_GUARD_PASS.verdict" 'RT_GUARD_PASS fail=0'
need "flood verdict" "${bundle}/04-FLOOD.verdict" 'RT_GUARD_FLOOD_PASS fail=0'

if [[ "${FAIL}" -gt 0 ]]; then
  echo "SCX1202_MATRIX_BUNDLE_VERIFY=FAIL count=${FAIL}" >&2
  exit 1
fi

echo "SCX1202_MATRIX_BUNDLE_VERIFY=PASS bundle=${bundle} checks=12/12"
exit 0
