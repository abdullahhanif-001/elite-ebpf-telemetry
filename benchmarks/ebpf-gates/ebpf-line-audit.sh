#!/usr/bin/env bash
# ebpf-line-audit.sh — hash audit local BPF sources; optional VPS compare.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${OUR_GOAL_DIR}/audit/line-audit-${STAMP}.txt"
VPS_HOST="${SCX_VPS_HOST:-contabo-server}"
VPS_ROOT="${ELITE_SRC:-/opt/elite/src}"
FAIL=0

ebpf_ensure_our_goal
mkdir -p "${OUR_GOAL_DIR}/audit"

log() { echo "$*" | tee -a "${OUT}"; }
log "=== ebpf-line-audit ${STAMP} ==="

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    wc -c < "$1"
  fi
}

while IFS= read -r -d '' f; do
  rel="${f#${ROOT}/}"
  rel="${rel//\\//}"
  lh="$(hash_file "${f}")"
  vps_h=""
  if ssh -o ConnectTimeout=8 -o BatchMode=yes "${VPS_HOST}" "test -f ${VPS_ROOT}/${rel}" 2>/dev/null; then
    vps_h="$(ssh -o ConnectTimeout=8 -o BatchMode=yes "${VPS_HOST}" "sha256sum ${VPS_ROOT}/${rel} 2>/dev/null | awk '{print \$1}'" 2>/dev/null || true)"
  fi
  if [[ -n "${vps_h}" && "${vps_h}" != "${lh}" ]]; then
    log "DRIFT ${rel} local=${lh} vps=${vps_h}"
    FAIL=$((FAIL + 1))
  else
    log "OK ${rel} hash=${lh} vps=${vps_h:-SKIP}"
  fi
done < <(find "${ROOT}/bpf" "${ROOT}/contrib/sched-ext" -type f \( -name '*.c' -o -name '*.h' -o -name '*.bpf.c' -o -name '*.bpf.h' -o -name '*.patch' \) -print0 2>/dev/null)

# Orphan check
if [[ -f "${ROOT}/bpf/DEPRECATED_ORPHANS.md" ]]; then
  log "ORPHAN_MARKER=OK bpf/DEPRECATED_ORPHANS.md"
else
  log "ORPHAN_MARKER=MISSING"
  FAIL=$((FAIL + 1))
fi

# Stub check: tracetasklatency
if grep -q 'stub\|TODO\|not implemented' "${ROOT}/pkg/exporter/probe/tracetasklatency/tasklatency.go" 2>/dev/null; then
  log "STUB tracetasklatency (documented)"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  log "LINE_AUDIT_PASS fail=0"
  our_goal_log "D1_line_audit" "PASS" "${OUT}" "no drift"
else
  log "LINE_AUDIT_FAIL fail=${FAIL}"
  our_goal_log "D1_line_audit" "FAIL" "${OUT}" "drift=${FAIL}"
  exit 1
fi
