#!/usr/bin/env bash
# verify-scx-1202-evidence.sh — static check of committed SCX#1202 + CHALLENGE_PROOF bundles.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID_BASE="${ROOT}/docs/evidence/scx-1202"

latest_verification="$(ls -td "${EVID_BASE}"/VERIFICATION_* 2>/dev/null | head -1 || true)"
latest_challenge="$(ls -td "${EVID_BASE}"/CHALLENGE_PROOF_* 2>/dev/null | head -1 || true)"

if [[ -z "${latest_verification}" && -z "${latest_challenge}" ]]; then
  echo "FAIL: no VERIFICATION_* or CHALLENGE_PROOF_* bundle under ${EVID_BASE}" >&2
  exit 1
fi

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

verify_verification_bundle() {
  local latest="$1"
  echo "Checking VERIFICATION bundle: ${latest}"

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
}

verify_challenge_bundle() {
  local latest="$1"
  echo "Checking CHALLENGE_PROOF bundle: ${latest}"

  require_file "${latest}/00-preflight.txt"
  require_file "${latest}/MANIFEST.json"
  require_file "${latest}/CHALLENGE_VERDICT.txt"
  require_file "${latest}/SUMMARY.md"
  require_file "${latest}/tier1/01-RT_GUARD_PASS.verdict"
  require_file "${latest}/tier2/ANDREA_PROOF.verdict"
  require_file "${latest}/tier2/04-FLOOD.verdict"
  require_file "${latest}/tier3/02-HOLY_GRAIL.verdict"
  require_file "${latest}/tier4/03-GLOBAL.verdict"

  require_grep "${latest}/00-preflight.txt" 'CONFIG_SCHED_CLASS_EXT=y' 'challenge preflight sched_ext'
  require_grep "${latest}/CHALLENGE_VERDICT.txt" 'LINUX_EBPF_CHALLENGE_PASS fail=0' 'Challenge master verdict'
  require_grep "${latest}/tier1/01-RT_GUARD_PASS.verdict" 'RT_GUARD_PASS fail=0' 'Challenge T1 RT_GUARD'
  require_grep "${latest}/tier2/ANDREA_PROOF.verdict" 'ANDREA_PROOF_PASS fail=0' 'Challenge Andrea proof'
  require_grep "${latest}/tier2/04-FLOOD.verdict" 'RT_GUARD_FLOOD_PASS fail=0' 'Challenge flood'
  require_grep "${latest}/tier3/02-HOLY_GRAIL.verdict" 'HOLY_GRAIL_1202_SOLVED=YES' 'Challenge Holy Grail'
  require_grep "${latest}/tier3/02-HOLY_GRAIL.verdict" 'checks=12/12' 'Challenge Holy Grail 12/12'
  require_grep "${latest}/tier4/03-GLOBAL.verdict" 'fail=0|GLOBAL result=PASS' 'Challenge global eBPF'

  if [[ -f "${latest}/tier1/01-rt-guard-pass.log" ]] && grep -qE 'SKIP scx_bpfland|SKIP scx_loader' "${latest}/tier1/01-rt-guard-pass.log" 2>/dev/null; then
    echo "FAIL Challenge T1: G6 SKIP in tier1 log" >&2
    FAIL=$((FAIL + 1))
  elif [[ -f "${latest}/tier1/01-rt-guard-pass.log" ]]; then
    echo "OK   Challenge T1: no G6 SKIP"
  else
    echo "OK   Challenge T1: log not committed (verdict checked)"
  fi
}

[[ -n "${latest_verification}" ]] && verify_verification_bundle "${latest_verification}"
[[ -n "${latest_challenge}" ]] && verify_challenge_bundle "${latest_challenge}"

if [[ "${FAIL}" -gt 0 ]]; then
  echo "SCX1202_EVIDENCE_VERIFY=FAIL count=${FAIL}" >&2
  exit 1
fi

echo "SCX1202_EVIDENCE_VERIFY=PASS"
[[ -n "${latest_verification}" ]] && echo "  verification=${latest_verification}"
[[ -n "${latest_challenge}" ]] && echo "  challenge=${latest_challenge}"
exit 0
