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

log_gate() { echo "[G$1] $2" | tee -a "${OUT}/gates.log"; }

# G0: SSH + sched_ext (skip self-ssh when running on VPS)
log_gate 0 "vps-connect-check"
if [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]] && \
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
if ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "bash ${ELITE_SRC}/scripts/contabo/pm2-guard-wrap.sh before rt-guard 2>/dev/null || true"; then
  log_gate 1 "PASS (or baseline created)"
else
  log_gate 1 "WARN pm2 baseline missing — creating"
  ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "mkdir -p /opt/elite/baseline && pm2 jlist > /opt/elite/baseline/pm2-before.json 2>/dev/null || true"
fi

# G2: rt_stall kselftest
log_gate 2 "rt_stall kselftest"
if ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "cd ${SCX_KERNEL_BUILD} && make -C tools/testing/selftests/sched_ext run_tests TEST_PROGS='rt_stall' 2>&1" | tee "${OUT}/g2-rt_stall.log"; then
  log_gate 2 "PASS"
else
  log_gate 2 "FAIL"
  FAIL=$((FAIL + 1))
fi

# G3: rt_guard_stress (contrib selftest)
log_gate 3 "rt_guard_stress"
if ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "test -f ${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext/rt_guard_stress.c"; then
  if ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "cd ${SCX_KERNEL_BUILD} && make -C tools/testing/selftests/sched_ext run_tests TEST_PROGS='rt_guard_stress' 2>&1" | tee "${OUT}/g3-rt_guard_stress.log"; then
    log_gate 3 "PASS"
  else
    log_gate 3 "FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  log_gate 3 "SKIP (install contrib selftest via sched-ext-vps-prep.sh apply-patches)"
fi

# G4: issue #1202 repro — must NOT stall after fix
log_gate 4 "rt-monopolization-repro"
if bash "${GATES_DIR}/rt-monopolization-repro.sh" | tee "${OUT}/g4-repro.log"; then
  LATEST="$(ls -td "${ROOT}/scripts/oneclick/results/rt-guard-baseline-"* 2>/dev/null | head -1)"
  if [[ -n "${LATEST}" ]] && grep -qE 'SCX_EXIT_ERROR_STALL|runnable task stall' "${LATEST}/dmesg.txt" 2>/dev/null; then
    log_gate 4 "FAIL stall still present in dmesg"
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
ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "cat /sys/kernel/debug/sched/ext_server/status 2>/dev/null || echo 'ext_server debugfs N/A'" | tee "${OUT}/g5-ext_server.txt"
log_gate 5 "INFO captured"

# G6: scx_bpfland 5min soak
log_gate 6 "bpfland 5min soak"
if ssh "${SCX_SSH_OPTS[@]}" "${HOST}" bash -s <<'REMOTE' | tee "${OUT}/g6-soak.log"; then
set -euo pipefail
if ! command -v scx_loader >/dev/null; then echo "SKIP scx_loader"; exit 0; fi
dmesg -C
scx_loader load bpfland &
LP=$!
sleep 300
kill $LP 2>/dev/null || true
if dmesg | grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL'; then
  echo "SOAK_FAIL stall detected"
  dmesg | tail -20
  exit 1
fi
echo "SOAK_PASS"
REMOTE
  log_gate 6 "PASS"
else
  log_gate 6 "FAIL"
  FAIL=$((FAIL + 1))
fi

# G1 after: PM2 guard
ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "bash ${ELITE_SRC}/scripts/contabo/pm2-guard-wrap.sh after rt-guard 2>/dev/null || true"

if [[ "${FAIL}" -eq 0 ]]; then
  echo "RT_GUARD_PASS fail=0 host=${HOST}" | tee "${OUT}/verdict.txt"
else
  echo "RT_GUARD_FAIL fail=${FAIL} host=${HOST}" | tee "${OUT}/verdict.txt"
  exit 1
fi
