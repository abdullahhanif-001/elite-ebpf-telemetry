#!/usr/bin/env bash
# verify-scx-1202-evidence.sh — strict static + log cross-check of SCX#1202 evidence bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID_BASE="${ROOT}/docs/evidence/scx-1202"
STRICT="${SCX1202_STRICT:-1}"

latest="$(ls -td "${EVID_BASE}"/VERIFICATION_* 2>/dev/null | head -1 || true)"
if [[ -z "${latest}" ]]; then
  echo "FAIL: no VERIFICATION_* bundle under ${EVID_BASE}" >&2
  exit 1
fi

echo "Checking evidence bundle: ${latest}"
FAIL=0

require_file() {
  local f="$1"
  if [[ ! -f "${f}" ]]; then
    echo "FAIL missing ${f}" >&2
    FAIL=$((FAIL + 1))
  fi
}

require_grep() {
  local file="$1" pattern="$2" label="$3"
  if ! grep -qE "${pattern}" "${file}" 2>/dev/null; then
    echo "FAIL ${label}: pattern '${pattern}' not in ${file}" >&2
    FAIL=$((FAIL + 1))
  else
    echo "OK   ${label}"
  fi
}

require_not_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "${pattern}" "${file}" 2>/dev/null; then
    echo "FAIL ${label}: forbidden '${pattern}' in ${file}" >&2
    FAIL=$((FAIL + 1))
  else
    echo "OK   ${label}"
  fi
}

require_file "${latest}/00-preflight.txt"
require_file "${latest}/MANIFEST.json"
require_file "${latest}/01-RT_GUARD_PASS.verdict"
require_file "${latest}/01-RT_GUARD_PASS.verdict"
matrix_verdict=""
for cand in "${latest}/02-SCX1202_MATRIX.verdict" "${latest}/02-HOLY_GRAIL.verdict"; do
  [[ -f "${cand}" ]] && matrix_verdict="${cand}" && break
done
if [[ -z "${matrix_verdict}" ]]; then
  echo "FAIL missing 02-SCX1202_MATRIX.verdict (or legacy 02-HOLY_GRAIL.verdict)" >&2
  FAIL=$((FAIL + 1))
fi
require_file "${latest}/03-GLOBAL.verdict"
require_file "${latest}/04-FLOOD.verdict"
require_file "${latest}/01-rt-guard-pass.log"
require_file "${latest}/04-flood-safe.log"

require_grep "${latest}/00-preflight.txt" 'CONFIG_SCHED_CLASS_EXT=y' 'preflight sched_ext'
require_grep "${latest}/01-RT_GUARD_PASS.verdict" 'RT_GUARD_PASS fail=0' 'RT_GUARD_PASS verdict'
require_grep "${matrix_verdict:-${latest}/02-HOLY_GRAIL.verdict}" 'SCX1202_MATRIX_PASS=YES' 'SCX1202 gate matrix verdict'
require_grep "${matrix_verdict:-${latest}/02-HOLY_GRAIL.verdict}" 'checks=12/12' 'SCX1202 gate matrix 12/12'
require_grep "${latest}/03-GLOBAL.verdict" 'fail=0|GLOBAL result=PASS' 'Global aggregate verdict'
require_grep "${latest}/04-FLOOD.verdict" 'RT_GUARD_FLOOD_PASS fail=0|FLOOD_SAFE_GATE_PASS' 'Flood verdict'

if [[ "${STRICT}" == "1" ]]; then
  echo "--- strict log cross-checks (no SKIP / no stale flood graft) ---"

  # sched_ext host must have scx_loader in PATH at capture time
  if grep -q 'CONFIG_SCHED_CLASS_EXT=y' "${latest}/00-preflight.txt" 2>/dev/null; then
    if grep -qE 'scx_loader=not_in_path|scx_loader not found' "${latest}/00-preflight.txt" 2>/dev/null; then
      echo "FAIL preflight: sched_ext kernel but scx_loader missing from PATH" >&2
      FAIL=$((FAIL + 1))
    elif ! grep -qE '^scx_loader=/' "${latest}/00-preflight.txt" 2>/dev/null; then
      echo "FAIL preflight: sched_ext kernel but no scx_loader=/<path> line in fingerprint" >&2
      FAIL=$((FAIL + 1))
    else
      echo "OK   preflight scx_loader present"
    fi
  fi

  require_not_grep "${latest}/01-rt-guard-pass.log" 'LOADER=SKIP' 'rt-guard: no LOADER=SKIP on sched_ext proof'
  require_not_grep "${latest}/01-rt-guard-pass.log" '\[G4\] FAIL' 'rt-guard: G4 must not FAIL'
  require_not_grep "${latest}/01-rt-guard-pass.log" '\[G6\] SKIP' 'rt-guard: G6 must not SKIP on sched_ext'
  require_not_grep "${latest}/01-rt-guard-pass.log" 'RT_GUARD_FAIL' 'rt-guard: no RT_GUARD_FAIL in log'

  require_not_grep "${latest}/04-flood-safe.log" 'FLOOD_SAFE_GATE_FAIL' 'flood-safe: preflight must pass'
  require_not_grep "${latest}/04-flood-safe.log" 'fail=1' 'flood-safe: no fail=1 in flood log'

  # MANIFEST must declare FULL proof (not historical partial)
  if grep -q '"status"[[:space:]]*:[[:space:]]*"FULL"' "${latest}/MANIFEST.json" 2>/dev/null; then
    echo "OK   MANIFEST status=FULL"
  else
    echo "FAIL MANIFEST: missing status=FULL (bundle is provisional/partial)" >&2
    FAIL=$((FAIL + 1))
  fi

  # Optional: commit pin when SCX1202_PIN_COMMIT=1
  if [[ "${SCX1202_PIN_COMMIT:-0}" == "1" ]]; then
    want="$(cd "${ROOT}" && git rev-parse HEAD 2>/dev/null || echo unknown)"
    got="$(grep -oE '"commit_sha"[[:space:]]*:[[:space:]]*"[^"]+"' "${latest}/MANIFEST.json" | sed 's/.*"\([^"]*\)"$/\1/' || true)"
    if [[ "${got}" != "${want}" ]]; then
      echo "FAIL commit_sha mismatch: bundle=${got} HEAD=${want}" >&2
      FAIL=$((FAIL + 1))
    else
      echo "OK   commit_sha matches HEAD"
    fi
  fi
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "SCX1202_EVIDENCE_VERIFY=FAIL count=${FAIL} strict=${STRICT}" >&2
  exit 1
fi

echo "SCX1202_EVIDENCE_VERIFY=PASS bundle=${latest} strict=${STRICT}"
exit 0
