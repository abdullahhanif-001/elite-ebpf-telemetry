#!/usr/bin/env bash
# our-goal-log.sh — append pass/fail rows to OUR_GOAL.md ledger.
set -euo pipefail

our_goal_log() {
  local phase="${1:?phase}" result="${2:?result}" artifact="${3:-}" notes="${4:-}"
  local root dir ts host
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  dir="${OUR_GOAL_DIR:-${root}/scripts/oneclick/results/our-goal}"
  mkdir -p "${dir}/audit" "${dir}/phases"
  ts="$(date -u +%Y-%m-%dT%H:%MZ)"
  host="$(hostname 2>/dev/null || echo unknown)"
  if [[ ! -f "${dir}/OUR_GOAL.md" ]]; then
    cat > "${dir}/OUR_GOAL.md" <<'HDR'
# our-goal — Global eBPF Verification Ledger

| timestamp | phase | host | result | artifact | notes |
|-----------|-------|------|--------|----------|-------|
HDR
  fi
  # escape pipes in notes
  notes="${notes//|/\\|}"
  artifact="${artifact//|/\\|}"
  echo "| ${ts} | ${phase} | ${host} | ${result} | ${artifact} | ${notes} |" >> "${dir}/OUR_GOAL.md"
  echo "[${ts}] ${phase} ${result} ${artifact} ${notes}" >> "${dir}/run.log"
  echo "OUR_GOAL_LOG phase=${phase} result=${result}"
}
