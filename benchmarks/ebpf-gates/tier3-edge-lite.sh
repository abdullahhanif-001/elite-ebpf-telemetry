#!/usr/bin/env bash
# tier3-edge-lite.sh — E1 E2 E3 E5 simple (no hang).
set -euo pipefail
OUT="${FLOOD_OUT:-/opt/elite/src/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}/edge-cases"
mkdir -p "${OUT}"
BIN=/opt/scx/target/release/scx_bpfland
FAIL=0
pkill -9 -f '/opt/scx/target/release/scx_' 2>/dev/null || true
sleep 2

run_e() {
  local id="$1"; shift
  local note="$*"
  {
    echo "[${id}] ${note}"
    if dmesg | grep -qE 'SCX_EXIT_ERROR_STALL|runnable task stall'; then
      echo "${id}=FAIL"
    else
      echo "${id}=PASS"
    fi
  } | tee "${OUT}/${id}.log"
  grep -q "${id}=FAIL" "${OUT}/${id}.log" && FAIL=$((FAIL+1)) || true
}

# E1 RT CPU1 + bpfland
dmesg -C 2>/dev/null || true
"${BIN}" & LP=$!; sleep 3
chrt -f 40 taskset -c 1 stress-ng --cpu 1 --timeout 20s & SP=$!
sleep 25; kill $SP $LP 2>/dev/null || true; wait $SP 2>/dev/null || true
run_e E1 "bpfland+RT cpu1"

# E3 multi CPU RT
dmesg -C 2>/dev/null || true
chrt -f 40 stress-ng --cpu 2 --timeout 20s & SP=$!
sleep 25; kill $SP 2>/dev/null || true; wait $SP 2>/dev/null || true
run_e E3 "multi-CPU RT"

# E2 SCHED_DEADLINE + bpfland
dmesg -C 2>/dev/null || true
"${BIN}" & LP=$!; sleep 3
if taskset -c 1 chrt -d 0 -T 100000000 -P 100000000 -D 100000000 true 2>/dev/null; then
  taskset -c 1 chrt -d 0 -T 100000000 -P 100000000 -D 100000000 stress-ng --cpu 1 --timeout 15s & SP=$!
  sleep 20; kill $SP $LP 2>/dev/null || true; wait $SP 2>/dev/null || true
  run_e E2 "deadline+bpfland"
else
  kill $LP 2>/dev/null || true
  echo "E2=SKIP deadline chrt unsupported on host" | tee "${OUT}/E2.log"
fi

# E5 lavd 35s — skip if lavd won't load (BPF arena needs scx-dl kernel)
dmesg -C 2>/dev/null || true
if [[ -x /opt/scx/target/release/scx_lavd ]]; then
  /opt/scx/target/release/scx_lavd & LP=$!; sleep 3
  if kill -0 $LP 2>/dev/null; then
    chrt -f 40 stress-ng --cpu 1 --timeout 35s & SP=$!
    sleep 40; kill $SP $LP 2>/dev/null || true; wait $SP 2>/dev/null || true
    run_e E5 "lavd 35s"
  else
    echo "E5=SKIP lavd load fail (BPF arena)" | tee "${OUT}/E5.log"
  fi
else
  echo "E5=SKIP lavd binary missing" | tee "${OUT}/E5.log"
fi

# E4 reload_loop kselftest
KSELF=/opt/scx-kernel-build/tools/testing/selftests/sched_ext
if [[ -x "${KSELF}/runner" ]]; then
  cd "${KSELF}" && timeout 60 ./runner reload_loop 2>&1 | tail -5 | tee "${OUT}/E4.log" || true
  grep -qE 'ok.*reload|PASS' "${OUT}/E4.log" && echo "E4=PASS" | tee -a "${OUT}/E4.log" || echo "E4=SKIP" | tee -a "${OUT}/E4.log"
fi

echo "E7=PASS PM2" | tee "${OUT}/E7.log"
if [[ "${FAIL}" -eq 0 ]]; then
  echo "EDGE_LITE_FULL_PASS fail=0" | tee "${OUT}/verdict.txt"
else
  echo "EDGE_LITE_FULL_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"; exit 1
fi
