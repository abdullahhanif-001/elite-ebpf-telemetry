#!/usr/bin/env bash
# verify-track1-track2-vm.sh — fail-closed VM checks (method: dont-be-bypass).
# Track 1: static SCX evidence + research gate (no ELITE_OFFLINE).
# Track 2: documents tetragon fix path; runs unit tests when TETRAGON_SRC set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REAL_ONLY=1
unset ELITE_OFFLINE || true
FAIL=0

log() { echo "[verify-track] $*"; }

log "=== Track 1: research gate (ELITE_OFFLINE forbidden) ==="
if bash "${ROOT}/scripts/research/run-research-gate.sh"; then
  log "RESEARCH_GATE=PASS"
else
  log "RESEARCH_GATE=FAIL"
  FAIL=$((FAIL + 1))
fi

log "=== Track 1: SCX#1202 committed evidence (strict static) ==="
if bash "${ROOT}/scripts/verify-scx-1202-evidence.sh"; then
  log "SCX1202_EVIDENCE=PASS"
else
  log "SCX1202_EVIDENCE=FAIL"
  FAIL=$((FAIL + 1))
fi

if bash "${ROOT}/scripts/verify-scx1202-matrix-from-bundle.sh" 2>/dev/null; then
  log "SCX1202_MATRIX_BUNDLE=PASS"
else
  log "SCX1202_MATRIX_BUNDLE=FAIL"
  FAIL=$((FAIL + 1))
fi

if [[ -f "/boot/config-$(uname -r)" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null; then
  log "sched_ext=YES — live rt-guard gates allowed on this host"
else
  log "sched_ext=NO — live SCX runtime NOT claimed on this VM (R0); static bundle only"
fi

TET="${TETRAGON_SRC:-${ROOT}/../tetragon}"
if [[ -d "${TET}/.git" ]]; then
  log "=== Track 2: tetragon mbset/selectors unit tests ==="
  if (cd "${TET}" && go test ./pkg/selectors/ -run TestWriteMatchBinariesPathDedupes -count=1); then
    log "TETRAGON_UNIT=PASS"
  else
    log "TETRAGON_UNIT=FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  log "TETRAGON_SRC missing — skip Track 2 go test (set TETRAGON_SRC=path/to/tetragon)"
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "VERIFY_TRACK1_TRACK2=FAIL fail=${FAIL}" >&2
  exit 1
fi
echo "VERIFY_TRACK1_TRACK2=PASS fail=0"
