#!/usr/bin/env bash
# Anti-fraud language gate for server category claims (CLAIM_CHARTER).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FAIL=0

check_file() {
  local f="$1"
  local line lower
  local -a lines=()
  [[ -f "${f}" ]] || return 0
  mapfile -t lines <"${f}"
  for line in "${lines[@]}"; do
    lower="$(printf '%s\n' "${line}" | tr '[:upper:]' '[:lower:]')"
    if printf '%s\n' "${lower}" | grep -Eq 'best in the world|number one ebpf|#1 ebpf'; then
      if printf '%s\n' "${lower}" | grep -Eq 'server_physics_vps|physics-speed|server.*bakeoff|bakeoff.*server'; then
        continue
      fi
      if [[ "${f}" == *CLAIM_CHARTER.md ]]; then
        continue
      fi
      echo "CLAIM_CHARTER_FAIL: ${f}: ${line}"
      FAIL=$((FAIL + 1))
    fi
    if printf '%s\n' "${lower}" | grep -Eq 'world best|holy grail|staff engineer|proven superior|unique to elite|independent auditor'; then
      if [[ "${f}" == *CLAIM_CHARTER.md ]]; then
        continue
      fi
      echo "CLAIM_CHARTER_FAIL hype: ${f}: ${line}"
      FAIL=$((FAIL + 1))
    fi
  done
}

check_file "${REPO_ROOT}/README.md"
check_file "${REPO_ROOT}/docs/OPS_PROVIDER_SCORE.md"
check_file "${REPO_ROOT}/docs/COMPETITIVE_PROOF.md"
check_file "${REPO_ROOT}/docs/COMPETITOR_BASELINE_MATRIX.md"
check_file "${REPO_ROOT}/docs/SERVER_CATEGORY_SCORECARD.md"

# Zero vendor hostname — must not appear anywhere in tracked source
if git -C "${REPO_ROOT}" grep -iE 'contabo' -- ':!*.plan.md' ':!scripts/oneclick/claim-charter-grep.sh' >/dev/null 2>&1; then
  echo "VENDOR_HOSTNAME_FAIL: contabo found in tracked files"
  git -C "${REPO_ROOT}" grep -iE 'contabo' -- ':!*.plan.md' ':!scripts/oneclick/claim-charter-grep.sh' || true
  FAIL=$((FAIL + 1))
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "VERDICT=CLAIM_CHARTER_FAIL count=${FAIL}"
  exit 1
fi
echo "VERDICT=CLAIM_CHARTER_PASS"
exit 0
