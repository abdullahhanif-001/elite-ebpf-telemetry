#!/usr/bin/env bash
# common.sh — research track guards (not product SCX evidence).
set -euo pipefail

research_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

RESEARCH_LEDGER_DIR="${RESEARCH_LEDGER_DIR:-$(research_repo_root)/scripts/oneclick/results/research}"
export REAL_ONLY="${REAL_ONLY:-1}"

research_forbid_offline() {
  if [[ "${ELITE_OFFLINE:-0}" == "1" ]]; then
    echo "FAIL: ELITE_OFFLINE=1 forbidden for bypass research (see research/BYPASS_CLAIM_CHARTER.md)" >&2
    exit 1
  fi
}

research_real_only_gate() {
  [[ "${REAL_ONLY}" == "1" ]] || {
    echo "FAIL: REAL_ONLY must be 1 for research gates" >&2
    exit 1
  }
  research_forbid_offline
}

research_ensure_ledger() {
  mkdir -p "${RESEARCH_LEDGER_DIR}/audit" "${RESEARCH_LEDGER_DIR}/preflight"
  local md="${RESEARCH_LEDGER_DIR}/RESEARCH_LEDGER.md"
  if [[ ! -f "${md}" ]]; then
    cat > "${md}" <<'HDR'
# Research ledger (bypass / kernel security)

Separate from `our-goal` / SCX product evidence. No offline bundle substitution.

| timestamp_utc | phase | host | result | artifact | notes |
|---------------|-------|------|--------|----------|-------|
HDR
  fi
}
