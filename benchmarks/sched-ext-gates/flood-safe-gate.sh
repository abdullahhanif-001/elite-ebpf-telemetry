#!/usr/bin/env bash
# flood-safe-gate.sh — pre-flight for 4vCPU/8GB VPS (SSH-stable resource caps).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

export FLOOD_SAFE_MODE="${FLOOD_SAFE_MODE:-1}"
FAIL=0

log() { echo "[safe-gate] $*"; }

if [[ "$(hostname 2>/dev/null)" != "${SCX_EXPECTED_HOST}" ]]; then
  log "WARN hostname=$(hostname) expected=${SCX_EXPECTED_HOST}"
fi

k="$(uname -r)"
if [[ -f "/boot/config-${k}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-${k}"; then
  log "sched_ext=YES kernel=${k}"
else
  log "FAIL sched_ext=NO"
  FAIL=$((FAIL + 1))
fi

if swapon --show 2>/dev/null | grep -q .; then
  log "swap=YES"
else
  log "FAIL swap inactive"
  FAIL=$((FAIL + 1))
fi

avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
avail_mb=$((avail_kb / 1024))
if [[ "${avail_mb}" -ge "${FLOOD_MIN_AVAIL_MB}" ]]; then
  log "mem_avail=${avail_mb}MB (>=${FLOOD_MIN_AVAIL_MB}MB)"
else
  log "FAIL mem_avail=${avail_mb}MB < ${FLOOD_MIN_AVAIL_MB}MB"
  FAIL=$((FAIL + 1))
fi

load_1="$(awk '{print $1}' /proc/loadavg)"
load_ok="$(python3 -c "print(1 if float('${load_1}') < float('${FLOOD_MAX_LOAD}') else 0)")"
if [[ "${load_ok}" == "1" ]]; then
  log "load_1m=${load_1} (<${FLOOD_MAX_LOAD})"
else
  log "FAIL load_1m=${load_1} >= ${FLOOD_MAX_LOAD}"
  FAIL=$((FAIL + 1))
fi

if pgrep -x make >/dev/null 2>&1 || pgrep -f 'cargo build' >/dev/null 2>&1; then
  log "FAIL kernel/cargo build running — stop before flood"
  FAIL=$((FAIL + 1))
else
  log "no_build_jobs=OK"
fi

if pgrep -f 'rt-guard-heavy-flood' >/dev/null 2>&1; then
  log "WARN stale rt-guard-heavy-flood — run recovery first"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "FLOOD_SAFE_GATE_PASS host=$(hostname) avail_mb=${avail_mb} load=${load_1}"
  exit 0
fi
echo "FLOOD_SAFE_GATE_FAIL fail=${FAIL}"
exit 1
