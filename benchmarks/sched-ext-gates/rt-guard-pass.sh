#!/usr/bin/env bash
# rt-guard-pass.sh — full REAL gate suite G0-G6 on Contabo VPS.
# shellcheck disable=SC2029
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

GATES_DIR="$(script_dir)"
ROOT="$(repo_root)"
HOST="${SCX_VPS_HOST}"
OUT="${ROOT}/scripts/oneclick/results/rt-guard-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"
FAIL=0

# When executed on the VPS itself, skip SSH hops (self-ssh breaks without localhost keys).
RUN_LOCAL=0
if [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]]; then
  RUN_LOCAL=1
fi

log_gate() { echo "[G$1] $2" | tee -a "${OUT}/gates.log"; }

sched_ext_enabled() {
  if [[ "${RUN_LOCAL}" -eq 1 ]]; then
    [[ -f "/boot/config-$(uname -r)" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null
  else
    vps_cmd "test -f /boot/config-\$(uname -r) && grep -q '^CONFIG_SCHED_CLASS_EXT=y' /boot/config-\$(uname -r)" 2>/dev/null
  fi
}

vps_cmd() {
  if [[ "${RUN_LOCAL}" -eq 1 ]]; then
    bash -c "$*"
  else
    ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "$*"
  fi
}

# G0: SSH + sched_ext (skip self-ssh when running on VPS)
log_gate 0 "vps-connect-check"
if [[ "${RUN_LOCAL}" -eq 1 ]] && \
   [[ -f "/boot/config-$(uname -r)" ]] && \
   grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null; then
  echo "VPS_CONNECT_PASS host=${SCX_EXPECTED_HOST} (local)" | tee "${OUT}/g0-connect.log"
  log_gate 0 "PASS local"
elif bash "${GATES_DIR}/vps-connect-check.sh" | tee "${OUT}/g0-connect.log"; then
  log_gate 0 "PASS"
else
  log_gate 0 "FAIL"
  FAIL=$((FAIL + 1))
fi

# G1: PM2 guard before
log_gate 1 "pm2-guard before"
if vps_cmd "bash ${ELITE_SRC}/scripts/contabo/pm2-guard-wrap.sh before rt-guard 2>/dev/null || true"; then
  log_gate 1 "PASS (or baseline created)"
else
  log_gate 1 "WARN pm2 baseline missing — creating"
  vps_cmd "mkdir -p /opt/elite/baseline && pm2 jlist > /opt/elite/baseline/pm2-before.json 2>/dev/null || true" || true
fi

# G2: rt_stall kselftest
log_gate 2 "rt_stall kselftest"
if vps_cmd "cd ${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext && ./runner rt_stall 2>&1" | tee "${OUT}/g2-rt_stall.log"; then
  if grep -qE 'ok .* rt_stall|TEST: rt_stall' "${OUT}/g2-rt_stall.log" && \
     ! grep -qE 'not ok .* rt_stall|FAIL.*rt_stall' "${OUT}/g2-rt_stall.log"; then
    log_gate 2 "PASS"
  else
    log_gate 2 "FAIL (rt_stall subtest missing or failed)"
    FAIL=$((FAIL + 1))
  fi
else
  log_gate 2 "FAIL"
  FAIL=$((FAIL + 1))
fi

# G3: rt_guard_stress (contrib selftest)
log_gate 3 "rt_guard_stress"
if vps_cmd "test -f ${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext/rt_guard_stress.c"; then
  if vps_cmd "cd ${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext && ./runner rt_guard_stress 2>&1" | tee "${OUT}/g3-rt_guard_stress.log"; then
    if grep -q '60s soak with RT+EXT' "${OUT}/g3-rt_guard_stress.log"; then
      log_gate 3 "PASS"
    else
      log_gate 3 "FAIL (soak subtest missing)"
      FAIL=$((FAIL + 1))
    fi
  else
    log_gate 3 "FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  if sched_ext_enabled; then
    log_gate 3 "FAIL (rt_guard_stress missing on sched_ext kernel)"
    FAIL=$((FAIL + 1))
  else
    log_gate 3 "SKIP (sched_ext not enabled)"
  fi
fi

# G4: issue #1202 repro — must NOT stall after fix
log_gate 4 "rt-monopolization-repro"
if RUN_LOCAL="${RUN_LOCAL}" bash "${GATES_DIR}/rt-monopolization-repro.sh" | tee "${OUT}/g4-repro.log"; then
  LATEST="$(ls -td "${ROOT}/scripts/oneclick/results/rt-guard-baseline-"* 2>/dev/null | head -1)"
  if [[ -n "${LATEST}" ]] && grep -qE 'SCX_EXIT_ERROR_STALL|runnable task stall' "${LATEST}/dmesg.txt" 2>/dev/null; then
    log_gate 4 "FAIL stall still present in dmesg"
    FAIL=$((FAIL + 1))
  elif grep -q 'STALL_DETECTED=YES' "${OUT}/g4-repro.log" 2>/dev/null; then
    log_gate 4 "FAIL stall detected in repro"
    FAIL=$((FAIL + 1))
  elif sched_ext_enabled && grep -qE 'LOADER=SKIP' "${OUT}/g4-repro.log" 2>/dev/null; then
    log_gate 4 "FAIL scx_loader required on sched_ext kernel"
    FAIL=$((FAIL + 1))
  else
    log_gate 4 "PASS no stall"
  fi
else
  log_gate 4 "FAIL repro script error"
  FAIL=$((FAIL + 1))
fi

# G5: ext_server debugfs
log_gate 5 "ext_server status"
vps_cmd "cat /sys/kernel/debug/sched/ext_server/status 2>/dev/null || echo 'ext_server debugfs N/A'" | tee "${OUT}/g5-ext_server.txt"
log_gate 5 "INFO captured"

# G6: scx_bpfland 5min soak (direct binary — scx_loader v1.x is DBus daemon, no `load` subcommand)
log_gate 6 "bpfland 5min soak"
if vps_cmd bash -s <<'REMOTE' | tee "${OUT}/g6-soak.log"; then
set -euo pipefail
BIN="${SCX_BIN_DIR:-/opt/scx/target/release}/scx_bpfland"
if [[ ! -x "${BIN}" ]]; then echo "SKIP scx_bpfland"; exit 0; fi
dmesg -C
"${BIN}" &
LP=$!
sleep 300
kill "${LP}" 2>/dev/null || true
pkill -f '/opt/scx/target/release/scx_bpfland' 2>/dev/null || true
if dmesg | grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL'; then
  echo "SOAK_FAIL stall detected"
  dmesg | tail -20
  exit 1
fi
echo "SOAK_PASS LOADER=bpfland"
REMOTE
  if grep -qE 'SKIP scx_bpfland|SKIP scx_loader' "${OUT}/g6-soak.log"; then
    if sched_ext_enabled; then
      log_gate 6 "FAIL scx_bpfland required on sched_ext kernel"
      FAIL=$((FAIL + 1))
    else
      log_gate 6 "SKIP (sched_ext not enabled)"
    fi
  elif grep -q 'SOAK_PASS' "${OUT}/g6-soak.log"; then
    log_gate 6 "PASS"
  else
    log_gate 6 "FAIL soak"
    FAIL=$((FAIL + 1))
  fi
else
  log_gate 6 "FAIL"
  FAIL=$((FAIL + 1))
fi

# G1 after: PM2 guard
vps_cmd "bash ${ELITE_SRC}/scripts/contabo/pm2-guard-wrap.sh after rt-guard 2>/dev/null || true" || true

if [[ "${FAIL}" -eq 0 ]]; then
  echo "RT_GUARD_PASS fail=0 host=${SCX_EXPECTED_HOST} kernel=$(uname -r 2>/dev/null || echo unknown)" | tee "${OUT}/verdict.txt"
else
  echo "RT_GUARD_FAIL fail=${FAIL} host=${SCX_EXPECTED_HOST}" | tee "${OUT}/verdict.txt"
  exit 1
fi
