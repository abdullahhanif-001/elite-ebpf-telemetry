#!/usr/bin/env bash
# research-log.sh — append to RESEARCH_LEDGER.md
set -euo pipefail
# shellcheck source=scripts/research/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

research_log() {
  local phase="${1:?phase}" result="${2:?result}" artifact="${3:-}" notes="${4:-}"
  research_ensure_ledger
  local ts host md
  ts="$(date -u +%Y-%m-%dT%H:%MZ)"
  host="$(hostname 2>/dev/null || echo unknown)"
  md="${RESEARCH_LEDGER_DIR}/RESEARCH_LEDGER.md"
  notes="${notes//|/\\|}"
  artifact="${artifact//|/\\|}"
  echo "| ${ts} | ${phase} | ${host} | ${result} | ${artifact} | ${notes} |" >> "${md}"
  echo "[${ts}] ${phase} ${result} ${artifact} ${notes}" >> "${RESEARCH_LEDGER_DIR}/run.log"
  echo "RESEARCH_LOG phase=${phase} result=${result}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  research_log "${@}"
fi
