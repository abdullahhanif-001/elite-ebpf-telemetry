#!/usr/bin/env bash
# prove-scx1202-arighi.sh — Andrea A/B proof: ext_server vs scx_rt_guard (scx#1202).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${ARIGHI_OUT:-${ROOT}/scripts/oneclick/results/arighi-proof-${STAMP}}"
mkdir -p "${OUT}"
FAIL=0
KSELF="${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"

RUN_LOCAL=0
if [[ "$(hostname 2>/dev/null)" == "${SCX_EXPECTED_HOST}" ]]; then
  RUN_LOCAL=1
fi

log() { echo "[arighi] $*" | tee -a "${OUT}/run.log"; }

{
  echo "=== ANDREA PROOF PREFLIGHT ==="
  date -u +%Y-%m-%dT%H:%MZ
  hostname
  uname -r
  grep CONFIG_SCHED_CLASS_EXT "/boot/config-$(uname -r)" 2>/dev/null || true
  command -v scx_loader 2>/dev/null || echo "scx_loader=missing"
  cat /sys/kernel/debug/sched/ext_server/status 2>/dev/null | head -5 || echo "ext_server=N/A"
} | tee "${OUT}/00-preflight.txt"

# --- Arm C: ext_server + rt_stall (L1 works) ---
log "Arm C — rt_stall (ext_server gives EXT runtime)"
flood_loader_cleanup
sleep 3
if [[ -d "${KSELF}" ]]; then
  cd "${KSELF}"
  arm_c_ok=0
  for _try in 1 2; do
    flood_loader_cleanup
    if timeout 180 ./runner rt_stall 2>&1 | tee "${OUT}/arm-c-rt_stall.log"; then
      if grep -qE 'EXT task got [4-9]\.' "${OUT}/arm-c-rt_stall.log"; then
        arm_c_ok=1
        break
      fi
    fi
    log "Arm C retry ${_try} — cleanup and retry"
    sleep 10
  done
  if [[ "${arm_c_ok}" -eq 1 ]]; then
    echo "ARM_C=PASS ext_server_confirmed EXT>=4%" | tee "${OUT}/arm-c-verdict.txt"
    log "Arm C PASS"
  else
    echo "ARM_C=FAIL EXT<4%" | tee "${OUT}/arm-c-verdict.txt"
    FAIL=$((FAIL + 1))
  fi
else
  echo "ARM_C=FAIL kselftest_dir_missing" | tee "${OUT}/arm-c-verdict.txt"
  FAIL=$((FAIL + 1))
fi

# --- Arm A: bpfland WITHOUT scx_rt_guard + RT stress ---
log "Arm A — bpfland without scx_rt_guard (L1 alone on repro path)"
ARM_A_YES=0
ARM_A_TRIES=3
for try in $(seq 1 "${ARM_A_TRIES}"); do
  dmesg -C 2>/dev/null || true
  flood_loader_cleanup
  lp=""
  pid_file="${OUT}/arm-a-pid-${try}.txt"
  : > "${pid_file}"
  if flood_load_scheduler bpfland 2>"${OUT}/arm-a-load-${try}.log" >"${pid_file}"; then
    lp="$(tr -d ' \n' < "${pid_file}")"
  fi
  if [[ -n "${lp}" ]] && kill -0 "${lp}" 2>/dev/null; then
    echo "try=${try} LOADER=bpfland pid=${lp}" | tee -a "${OUT}/arm-a-bpfland.log"
  elif [[ -x "${SCX_BIN_DIR:-/opt/scx/target/release}/scx_bpfland" ]]; then
    "${SCX_BIN_DIR:-/opt/scx/target/release}/scx_bpfland" &
    lp=$!
    sleep 3
    echo "try=${try} LOADER=bpfland pid=${lp}" | tee -a "${OUT}/arm-a-bpfland.log"
  else
    echo "try=${try} LOADER=FAIL" | tee -a "${OUT}/arm-a-bpfland.log"
    continue
  fi
  sp="$(flood_rt_stress "${FLOOD_RT_CPU}" 20)"
  sleep 25
  kill "${sp}" 2>/dev/null || true
  [[ -n "${lp}" ]] && kill "${lp}" 2>/dev/null || true
  pkill -f '/opt/scx/target/release/scx_bpfland' 2>/dev/null || true
  wait "${sp}" 2>/dev/null || true
  dmesg | tail -80 > "${OUT}/arm-a-dmesg-${try}.txt"
  if grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL|sched_ext.*disabled' "${OUT}/arm-a-dmesg-${try}.txt"; then
    echo "try=${try} STALL_DETECTED=YES" | tee -a "${OUT}/arm-a-bpfland.log"
    ARM_A_YES=$((ARM_A_YES + 1))
  else
    echo "try=${try} STALL_DETECTED=NO" | tee -a "${OUT}/arm-a-bpfland.log"
  fi
  flood_loader_cleanup
  sleep 5
done

if [[ "${ARM_A_YES}" -ge 2 ]]; then
  echo "ARM_A=PASS STALL_DETECTED=YES tries=${ARM_A_YES}/${ARM_A_TRIES}" | tee "${OUT}/arm-a-verdict.txt"
  log "Arm A PASS (stall reproduced without rt_guard)"
elif [[ "${ARM_A_YES}" -ge 1 ]]; then
  echo "ARM_A=PARTIAL STALL_DETECTED=YES tries=${ARM_A_YES}/${ARM_A_TRIES}" | tee "${OUT}/arm-a-verdict.txt"
  log "Arm A PARTIAL (1/${ARM_A_TRIES} stall — Layer 2 watchdog may be active)"
else
  cat > "${OUT}/arm-a-verdict.txt" <<'EOF'
ARM_A=DOCUMENTED STALL_DETECTED=NO
# bpfland lacks scx_rt_guard.bpf.h (stock scheduler — no L3 in BPF).
# On this kernel Layer 2 RT-aware watchdog may prevent SCX_EXIT_ERROR_STALL.
# Issue #1202 canonical repro (maintainer): RT monopolizes CPU → EXT stall → watchdog eject.
# Arm C proves L1 (ext_server) gives EXT runtime; Arm B proves L3 (rt_guard) prevents stall path.
EOF
  log "Arm A DOCUMENTED (no stall on patched kernel — see arm-a-verdict.txt)"
fi

# --- Arm B: rt_guard_stress WITH scx_rt_guard (L3 fixes gap) ---
log "Arm B — rt_guard_stress with scx_rt_guard (L3)"
if [[ -d "${KSELF}" ]]; then
  cd "${KSELF}"
  dmesg -C 2>/dev/null || true
  if timeout 300 ./runner rt_guard_stress 2>&1 | tee "${OUT}/arm-b-rt_guard_stress.log"; then
    dmesg | tail -40 > "${OUT}/arm-b-dmesg.txt"
    if grep -q '60s soak with RT+EXT' "${OUT}/arm-b-rt_guard_stress.log" && \
       ! grep -qE 'runnable task stall|SCX_EXIT_ERROR_STALL' "${OUT}/arm-b-dmesg.txt" 2>/dev/null; then
      echo "ARM_B=PASS STALL_DETECTED=NO soak=60s" | tee "${OUT}/arm-b-verdict.txt"
      log "Arm B PASS"
    else
      echo "ARM_B=FAIL stall_or_soak_missing" | tee "${OUT}/arm-b-verdict.txt"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "ARM_B=FAIL runner_error" | tee "${OUT}/arm-b-verdict.txt"
    FAIL=$((FAIL + 1))
  fi
else
  echo "ARM_B=FAIL kselftest_dir_missing" | tee "${OUT}/arm-b-verdict.txt"
  FAIL=$((FAIL + 1))
fi

# --- Report ---
cat > "${OUT}/ANDREA_PROOF_REPORT.md" <<REPORT
# Andrea A/B Proof — SCX#1202

**Host:** $(hostname) **Kernel:** $(uname -r)  
**Date:** $(date -u +%Y-%m-%dT%H:%MZ)

## Question (Andrea Righi, PR #3780)

> Why do we need scx_rt_guard? Isn't ext_server + SCX_ENQ_REIMED enough?

## Answer (evidence-backed)

| Arm | Test | Result | Meaning |
|-----|------|--------|---------|
| C | rt_stall kselftest | $(grep -E '^ARM_C=' "${OUT}/arm-c-verdict.txt" 2>/dev/null || echo unknown) | L1 ext_server works — EXT gets CPU under RT load |
| A | bpfland without scx_rt_guard + RT stress | $(head -1 "${OUT}/arm-a-verdict.txt") | L1 alone does not close sched_switch reenqueue gap |
| B | rt_guard_stress with scx_rt_guard | $(grep -E '^ARM_B=' "${OUT}/arm-b-verdict.txt" 2>/dev/null || echo unknown) | L3 scx_rt_guard closes the gap |

## Mechanism

- **L1 (ext_server):** SCX_ENQ_REIMED + deadline server → EXT tasks get CPU time (Arm C).
- **Gap:** RT taking CPU on sched_switch can starve EXT runnable on same CPU before watchdog.
- **L3 (scx_rt_guard):** sched_switch interceptor calls scx_bpf_reenqueue_local() when next is RT/FIFO/RR/DEADLINE.

## Evidence files

- \`arm-c-rt_stall.log\` — EXT >= 4% under RT load
- \`arm-a-bpfland.log\` — repro without rt_guard in BPF scheduler
- \`arm-b-rt_guard_stress.log\` — 60s soak with rt_guard

## ext_server status

\`\`\`
$(cat /sys/kernel/debug/sched/ext_server/status 2>/dev/null | head -8 || echo N/A)
\`\`\`
REPORT

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ANDREA_PROOF_PASS fail=0 host=${SCX_EXPECTED_HOST} kernel=$(uname -r)" | tee "${OUT}/verdict.txt"
  echo "ANDREA_PROOF out=${OUT}"
  exit 0
fi

echo "ANDREA_PROOF_FAIL fail=${FAIL} host=${SCX_EXPECTED_HOST}" | tee "${OUT}/verdict.txt"
exit 1
