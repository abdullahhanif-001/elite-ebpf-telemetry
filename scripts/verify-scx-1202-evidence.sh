#!/usr/bin/env bash
# verify-scx-1202-evidence.sh — static check of committed SCX#1202 evidence bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID_BASE="${ROOT}/docs/evidence/scx-1202"

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

require_file "${latest}/00-preflight.txt"
require_file "${latest}/MANIFEST.json"
require_file "${latest}/01-RT_GUARD_PASS.verdict"
require_file "${latest}/02-HOLY_GRAIL.verdict"
require_file "${latest}/03-GLOBAL.verdict"
require_file "${latest}/04-FLOOD.verdict"

require_grep "${latest}/00-preflight.txt" 'CONFIG_SCHED_CLASS_EXT=y' 'preflight sched_ext'
require_grep "${latest}/01-RT_GUARD_PASS.verdict" 'RT_GUARD_PASS fail=0' 'RT_GUARD_PASS'
require_grep "${latest}/02-HOLY_GRAIL.verdict" 'HOLY_GRAIL_1202_SOLVED=YES' 'Holy Grail'
require_grep "${latest}/02-HOLY_GRAIL.verdict" 'checks=12/12' 'Holy Grail 12/12'
require_grep "${latest}/03-GLOBAL.verdict" 'fail=0|GLOBAL result=PASS' 'Global aggregate'
require_grep "${latest}/04-FLOOD.verdict" 'RT_GUARD_FLOOD_PASS fail=0|FLOOD_SAFE_PASS|safe-gate.*PASS' 'Flood gate'

if [[ "${FAIL}" -gt 0 ]]; then
  echo "SCX1202_EVIDENCE_VERIFY=FAIL count=${FAIL}" >&2
  exit 1
fi

echo "SCX1202_EVIDENCE_VERIFY=PASS bundle=${latest}"
exit 0
