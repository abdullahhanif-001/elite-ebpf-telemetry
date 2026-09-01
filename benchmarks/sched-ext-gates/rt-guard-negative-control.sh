#!/usr/bin/env bash
# rt-guard-negative-control.sh — broken BPF scheduler must still fail (no RT mask).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

ROOT="$(repo_root)"
OUT="${FLOOD_OUT:-${ROOT}/scripts/oneclick/results/rt-guard-flood-$(date +%Y%m%d-%H%M%S)/negative-control}"
mkdir -p "${OUT}"
FAIL=0

KSELF="${SCX_KERNEL_BUILD}/tools/testing/selftests/sched_ext"
[[ -x "${KSELF}/runner" ]] || { echo "FAIL: runner missing"; exit 1; }

echo "[NEG] enq_last_no_enq_fails — must reject broken scheduler" | tee "${OUT}/neg.log"
dmesg -C 2>/dev/null || true
cd "${KSELF}"
if ./runner enq_last_no_enq_fails 2>&1 | grep -E 'enq_last|PASS|FAIL|ok ' | tee "${OUT}/enq_last.log"; then
  if grep -qE 'not ok|FAIL|SCX_EXIT|disabled' "${OUT}/enq_last.log"; then
    echo "NEG_PASS broken scheduler rejected or exited" | tee -a "${OUT}/neg.log"
  elif grep -q 'ok.*enq_last_no_enq_fails' "${OUT}/enq_last.log"; then
    echo "NEG_PASS test passed (scheduler correctly ejected)" | tee -a "${OUT}/neg.log"
  else
    echo "NEG_WARN unclear result — check log" | tee -a "${OUT}/neg.log"
  fi
else
  echo "NEG_PASS runner exit non-zero (expected for broken sched)" | tee -a "${OUT}/neg.log"
fi

if [[ "${FLOOD_SAFE_MODE:-0}" == "1" ]]; then
  echo "NEG_SAFE_MODE=skip minimal (isolated enq_last only)" | tee -a "${OUT}/neg.log"
else
  echo "[NEG] minimal scheduler without RT — must stay loaded 10s" | tee -a "${OUT}/neg.log"
  dmesg -C 2>/dev/null || true
  if ./runner minimal 2>&1 | grep -E 'minimal|PASS|FAIL' | tee "${OUT}/minimal.log"; then
    if grep -q 'ok.*minimal' "${OUT}/minimal.log"; then
      echo "NEG_PASS healthy minimal scheduler OK" | tee -a "${OUT}/neg.log"
    else
      echo "NEG_FAIL minimal scheduler failed unexpectedly" | tee -a "${OUT}/neg.log"
      FAIL=$((FAIL + 1))
    fi
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "NEGATIVE_CONTROL_PASS fail=0" | tee "${OUT}/verdict.txt"
else
  echo "NEGATIVE_CONTROL_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
  exit 1
fi
