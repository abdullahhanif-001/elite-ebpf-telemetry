#!/usr/bin/env bash
# Anti-fraud language gate for category #1 claims (CLAIM_CHARTER).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FAIL=0

check_file() {
  local f="$1"
  local line lower
  local -a lines=()
  [[ -f "${f}" ]] || return 0
  # Load first so we never read+write the same path in one pipeline (SC2094).
  mapfile -t lines <"${f}"
  for line in "${lines[@]}"; do
    lower="$(printf '%s\n' "${line}" | tr '[:upper:]' '[:lower:]')"
    if printf '%s\n' "${lower}" | grep -Eq 'best in the world|number one ebpf|#1 ebpf'; then
      if printf '%s\n' "${lower}" | grep -Eq 'physics_speed_vps|physics-speed|contabo.*bakeoff|bakeoff.*contabo'; then
        continue
      fi
      # Allowed inside CLAIM_CHARTER forbidden section
      if [[ "${f}" == *CLAIM_CHARTER.md ]]; then
        continue
      fi
      echo "CLAIM_CHARTER_FAIL: ${f}: ${line}"
      FAIL=$((FAIL + 1))
    fi
  done
}

check_file "${REPO_ROOT}/README.md"
check_file "${REPO_ROOT}/docs/WORLD_BEST_PROVIDER_SCORE.md"
check_file "${REPO_ROOT}/docs/COMPETITIVE_PROOF.md"
check_file "${REPO_ROOT}/docs/WORLD_EBPF_COMPARISON.md"
check_file "${REPO_ROOT}/docs/CATEGORY_NUMBER_ONE_SCORECARD.md"

if [[ "${FAIL}" -gt 0 ]]; then
  echo "VERDICT=CLAIM_CHARTER_FAIL count=${FAIL}"
  exit 1
fi
echo "VERDICT=CLAIM_CHARTER_PASS"
exit 0
