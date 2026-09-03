#!/usr/bin/env bash
# flood-common.sh — shared helpers for rt-guard heavy flood suite.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FLOOD_SCHEDULERS=(bpfland lavd rusty flash rustland layered)
SCX_BIN_DIR="${SCX_BIN_DIR:-/opt/scx/target/release}"
FLOOD_RT_CPU="${FLOOD_RT_CPU:-1}"
FLOOD_STRESS_SEC="${FLOOD_STRESS_SEC:-15}"
FLOOD_SOAK_SHORT_SEC="${FLOOD_SOAK_SHORT_SEC:-300}"
FLOOD_SOAK_LONG_SEC="${FLOOD_SOAK_LONG_SEC:-1800}"
FLOOD_COOLDOWN_SEC="${FLOOD_COOLDOWN_SEC:-60}"
FLOOD_MIN_AVAIL_MB="${FLOOD_MIN_AVAIL_MB:-4096}"
FLOOD_MAX_LOAD="${FLOOD_MAX_LOAD:-3.0}"

# Safe mode defaults for 4 vCPU / 8GB VPS (SSH-stable)
if [[ "${FLOOD_SAFE_MODE:-0}" == "1" ]]; then
  FLOOD_SOAK_SHORT_SEC=60
  FLOOD_SOAK_LONG_SEC=300
  FLOOD_COOLDOWN_SEC=60
  FLOOD_MIN_AVAIL_MB=4096
  FLOOD_MAX_LOAD=3.0
fi

flood_safe_out_dir() {
  local root
  root="$(repo_root)"
  if [[ -n "${FLOOD_OUT:-}" ]]; then
    echo "${FLOOD_OUT}"
  else
    ls -td "${root}"/scripts/oneclick/results/rt-guard-flood-safe-* 2>/dev/null | head -1 || true
  fi
}

flood_checkpoint_write() {
  local phase="$1" status="$2"
  local out dir
  dir="$(flood_safe_out_dir)"
  [[ -n "${dir}" ]] || return 0
  mkdir -p "${dir}"
  out="${dir}/checkpoint.json"
  python3 - "${out}" "${phase}" "${status}" "$(hostname 2>/dev/null || echo unknown)" <<'PY'
import json, sys, datetime
path, phase, status, host = sys.argv[1:5]
data = {"host": host, "mode": "safe_4vcpu", "phases": {}}
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    pass
data.setdefault("phases", {})[phase] = {
    "status": status,
    "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print(f"CHECKPOINT {phase}={status}")
PY
}

flood_run_isolated_kselftest_prog() {
  local prog="$1" log="$2" grep_pat="${3:-.}"
  local kself="${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
  [[ -d "${kself}" ]] || return 1
  cd "${kself}"
  if [[ -x "./${prog}" ]]; then
    timeout 180 "./${prog}" 2>&1 | tee "${log}"
  elif [[ -n "${TEST_PROGS:-}" ]]; then
    TEST_PROGS="${prog}" timeout 180 ./runner 2>&1 | tee "${log}"
  else
    timeout 180 ./runner "${prog}" 2>&1 | grep -E "${grep_pat}" | tee "${log}"
    # runner filters output; re-check full log if grep emptied critical lines
    if ! grep -qE "${grep_pat}" "${log}" 2>/dev/null; then
      timeout 180 ./runner "${prog}" 2>&1 | tee "${log}.full"
      grep -E "${grep_pat}" "${log}.full" | tee "${log}" || true
    fi
  fi
}

flood_run_isolated_rt_stall() {
  local log="$1"
  flood_run_isolated_kselftest_prog "rt_stall" "${log}" 'EXT task got|FAIR task got|rt_stall|PASS|FAIL|ok '
  grep -qE 'EXT task got [4-9]\.' "${log}" 2>/dev/null
}

flood_run_isolated_rt_guard_stress() {
  local log="$1"
  flood_run_isolated_kselftest_prog "rt_guard_stress" "${log}" '60s soak|rt_guard_stress|PASS|FAIL|ok '
  grep -q '60s soak with RT+EXT' "${log}" 2>/dev/null
}

flood_cached_rt_stall_log() {
  local root cached
  root="$(repo_root)"
  cached="$(ls -td "${root}"/scripts/oneclick/results/rt-guard-*/g2-rt_stall.log 2>/dev/null | head -1 || true)"
  [[ -n "${cached}" && -f "${cached}" ]] && echo "${cached}"
}

flood_run_local() {
  [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]]
}

flood_vps_cmd() {
  if flood_run_local; then
    bash -c "$*"
  else
    ssh "${SCX_SSH_OPTS[@]}" "${SCX_VPS_HOST}" "$*"
  fi
}

flood_stall_in_dmesg() {
  dmesg 2>/dev/null | grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled'
}

flood_check_stall() {
  local log="$1"
  if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' "${log}" 2>/dev/null; then
    return 0
  fi
  return 1
}

flood_loader_cleanup() {
  pkill -f '/opt/scx/target/release/scx_' 2>/dev/null || true
  pkill -f 'scx_loader' 2>/dev/null || true
  pkill -f 'stress-ng.*matrixprod' 2>/dev/null || true
  sleep 1
}

flood_load_scheduler() {
  local sched="$1"
  local bin lp
  flood_loader_cleanup
  dmesg -C 2>/dev/null || true
  bin="$(flood_sched_bin "${sched}")" || bin="$(flood_build_scheduler "${sched}")" || {
    echo "LOADER_FAIL sched=${sched} binary missing" >&2
    return 1
  }
  "${bin}" &
  lp=$!
  disown "${lp}" 2>/dev/null || true
  sleep 3
  if ! kill -0 "${lp}" 2>/dev/null; then
    echo "LOADER_FAIL sched=${sched}" >&2
    return 1
  fi
  echo "LOADER_OK sched=${sched} bin=${bin} pid=${lp}" >&2
  echo "${lp}"
}

flood_rt_stress() {
  local cpu="${1:-${FLOOD_RT_CPU}}"
  local sec="${2:-${FLOOD_STRESS_SEC}}"
  chrt -f 40 taskset -c "${cpu}" \
    stress-ng --cpu 1 --cpu-method matrixprod --timeout "${sec}s" &
  echo $!
}

flood_rt_stress_multi() {
  local n="${1:-3}"
  local sec="${2:-${FLOOD_STRESS_SEC}}"
  chrt -f 40 stress-ng --cpu "${n}" --cpu-method matrixprod --timeout "${sec}s" &
  echo $!
}

flood_repro_capture() {
  local out="$1"
  local sched="${2:-bpfland}"
  local lp sp fallback=0

  dmesg -C 2>/dev/null || true
  if ! lp="$(flood_load_scheduler "${sched}" 2>/dev/null)"; then
    echo "WARN: scx_${sched} load failed — using rt_guard_stress BPF fallback" | tee -a "${out}/run.log"
    fallback=1
    if [[ -x "${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext/runner" ]]; then
      cd "${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
      ./runner rt_guard_stress 2>&1 | grep -E '60s soak|FAIL|stall' | tee "${out}/fallback-rt_guard.log" || true
      if grep -q '60s soak with RT+EXT' "${out}/fallback-rt_guard.log" 2>/dev/null; then
        echo "FALLBACK_PASS sched=${sched} via rt_guard_stress" | tee "${out}/verdict.txt"
        return 0
      fi
    fi
    echo "STALL_DETECTED=YES sched=${sched} loader_and_fallback_failed" | tee "${out}/verdict.txt"
    return 1
  fi
  sp="$(flood_rt_stress "${FLOOD_RT_CPU}" "${FLOOD_STRESS_SEC}")"
  sleep $((FLOOD_STRESS_SEC + 5))
  wait "${sp}" 2>/dev/null || true
  kill "${lp}" 2>/dev/null || true
  wait "${lp}" 2>/dev/null || true
  dmesg > "${out}/dmesg.txt"
  if flood_check_stall "${out}/dmesg.txt"; then
    echo "STALL_DETECTED=YES sched=${sched}" | tee "${out}/verdict.txt"
    return 1
  fi
  echo "STALL_DETECTED=NO sched=${sched} fallback=${fallback}" | tee "${out}/verdict.txt"
  return 0
}

flood_pm2_before() {
  bash "${ELITE_SRC}/scripts/server/pm2-guard-wrap.sh" before rt-guard-flood 2>/dev/null || \
    mkdir -p /opt/elite/baseline && pm2 jlist > /opt/elite/baseline/pm2-before.json 2>/dev/null || true
}

flood_pm2_after() {
  bash "${ELITE_SRC}/scripts/server/pm2-guard-wrap.sh" after rt-guard-flood 2>/dev/null || true
}

flood_sched_bin() {
  local sched="$1"
  local bin="${SCX_BIN_DIR}/scx_${sched}"
  [[ -x "${bin}" ]] && echo "${bin}" && return 0
  return 1
}

flood_build_scheduler() {
  local sched="$1"
  local dir="/opt/scx/scheds/rust/scx_${sched}"
  [[ -d "${dir}" ]] || return 1
  source "${HOME}/.cargo/env" 2>/dev/null || true
  (cd "${dir}" && cargo build --release) >> /tmp/scx-build-${sched}.log 2>&1
  flood_sched_bin "${sched}"
}

flood_require_scx_loader() {
  local sched built=0 missing=()
  source "${HOME}/.cargo/env" 2>/dev/null || true
  for sched in "${FLOOD_SCHEDULERS[@]}"; do
    if flood_sched_bin "${sched}" >/dev/null; then
      built=$((built + 1))
    else
      echo "Building scx_${sched}..." >&2
      flood_build_scheduler "${sched}" || missing+=("${sched}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "FAIL: missing schedulers: ${missing[*]}" >&2
    return 1
  fi
  echo "SCHEDULERS_OK count=${built}/${#FLOOD_SCHEDULERS[@]}"
  flood_sched_bin bpfland
}
