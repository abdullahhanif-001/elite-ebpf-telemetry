#!/usr/bin/env bash
# code-audit-gate.sh — sched_ext contrib vs VPS kernel + binaries.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
GATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sched-ext-gates" && pwd)"
# shellcheck source=/dev/null
source "${GATES}/common.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${OUR_GOAL_DIR}/audit/code-audit-${STAMP}.txt"
FAIL=0
ebpf_ensure_our_goal
mkdir -p "${OUR_GOAL_DIR}/audit"

log() { echo "$*" | tee -a "${OUT}"; }
log "=== code-audit-gate ${STAMP} ==="

PATCH="${ROOT}/contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch"
[[ -f "${PATCH}" ]] && log "PATCH_OK ${PATCH}" || { log "PATCH_MISSING"; FAIL=$((FAIL + 1)); }

if [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]]; then
  EXT_C="${SCX_KERNEL_BUILD}/kernel/sched/ext.c"
  if grep -q scx_stall_caused_by_rt "${EXT_C}" 2>/dev/null; then
    log "LAYER2_LIVE=YES ext.c patched"
  else
    log "LAYER2_LIVE=NO"
    FAIL=$((FAIL + 1))
  fi
  k="$(uname -r)"
  if [[ -f "/boot/config-${k}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-${k}"; then
    log "sched_ext=YES kernel=${k}"
  else
    log "sched_ext=NO"
    FAIL=$((FAIL + 1))
  fi
  if [[ -f /proc/sys/kernel/ftrace_enabled ]]; then
    log "ftrace=YES"
  else
    log "ftrace=NO (Tier3 loader proof blocked)"
  fi
  KSELF="${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
  [[ -x "${KSELF}/runner" ]] && log "kselftest_runner=OK" || { log "kselftest_runner=MISSING"; FAIL=$((FAIL + 1)); }
  for sched in bpfland lavd rusty flash rustland layered; do
    bin="/opt/scx/target/release/scx_${sched}"
    [[ -x "${bin}" ]] && log "sched_bin_OK ${sched}" || log "sched_bin_SKIP ${sched}"
  done
else
  log "LOCAL_MODE — run on VPS for live kernel checks"
  ssh -o ConnectTimeout=15 "${SCX_VPS_HOST:-production-server}" \
    "grep -q scx_stall_caused_by_rt ${SCX_KERNEL_BUILD}/kernel/sched/ext.c && echo LAYER2_VPS=YES || echo LAYER2_VPS=NO" \
    | tee -a "${OUT}" || true
fi

HDR="${ROOT}/contrib/sched-ext/bpf/scx_rt_guard.bpf.h"
[[ -f "${HDR}" ]] && log "LAYER3_HDR=OK" || { log "LAYER3_HDR=MISSING"; FAIL=$((FAIL + 1)); }

if [[ "${FAIL}" -eq 0 ]]; then
  log "CODE_AUDIT_GATE_PASS fail=0"
  our_goal_log "D1_code_audit" "PASS" "${OUT}" "sched_ext artifacts"
else
  log "CODE_AUDIT_GATE_FAIL fail=${FAIL}"
  our_goal_log "D1_code_audit" "FAIL" "${OUT}" "fail=${FAIL}"
  exit 1
fi
