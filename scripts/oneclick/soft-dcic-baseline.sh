#!/usr/bin/env bash
# Soft DCIC baseline — synthetic L2/WSS thrash vs LC latency on VPS (Track A).
# Compares unprotected vs advise vs enforce. No Windows. No Hetzner.
set -euo pipefail

OUT_DIR="${SOFT_DCIC_BASELINE_OUT:-/tmp/elite-dcic-baseline-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${OUT_DIR}"
DURATION="${BASELINE_SECONDS:-20}"
THRASH_MB="${THRASH_MB:-64}"

log() { echo "[baseline] $*"; }

build_thrash() {
  cat > "${OUT_DIR}/l2_thrash.c" <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

int main(int argc, char **argv) {
  size_t mb = 64;
  int seconds = 20;
  if (argc > 1) mb = (size_t)atoi(argv[1]);
  if (argc > 2) seconds = atoi(argv[2]);
  size_t n = mb * 1024UL * 1024UL / sizeof(uint64_t);
  uint64_t *buf = aligned_alloc(64, n * sizeof(uint64_t));
  if (!buf) return 1;
  for (size_t i = 0; i < n; i++) buf[i] = i;
  /* pointer chase stride to defeat prefetch */
  for (size_t i = 0; i + 17 < n; i++) buf[i] = (uint64_t)(i + 17);
  buf[n - 1] = 0;
  time_t end = time(NULL) + seconds;
  volatile uint64_t idx = 0;
  uint64_t steps = 0;
  while (time(NULL) < end) {
    idx = buf[idx % n] % n;
    steps++;
  }
  printf("thrash_steps=%llu\n", (unsigned long long)steps);
  free(buf);
  return 0;
}
EOF
  cc -O2 -o "${OUT_DIR}/l2_thrash" "${OUT_DIR}/l2_thrash.c"
}

sample_lc() {
  local n=30
  local sum=0
  local sample
  for sample in $(seq 1 "${n}"); do
    : "${sample}"
    local v
    v="$(curl -s --connect-timeout 1 127.0.0.1:9103/metrics | awk '/^elite_dcic_lc_latency_seconds/{print $2; exit}')"
    if [[ -z "${v}" ]]; then v=0; fi
    sum="$(python3 -c "print(${sum}+${v})")"
    sleep 0.2
  done
  python3 -c "print(${sum}/${n})"
}

run_phase() {
  local name="$1"
  local mode="$2"
  log "phase=${name} mode=${mode}"
  systemctl stop elite-dcic.service 2>/dev/null || true
  # restart in desired mode
  sed -i "s|^ExecStart=.*|ExecStart=/usr/local/bin/elite-dcic -mode ${mode} -listen 127.0.0.1:9103 -capability /etc/elite/dcic-capability.json|" /etc/systemd/system/elite-dcic.service
  systemctl daemon-reload
  systemctl start elite-dcic.service
  sleep 2

  local pids=()
  # start 2 thrashers as BE noise
  "${OUT_DIR}/l2_thrash" "${THRASH_MB}" "${DURATION}" >"${OUT_DIR}/${name}-thrash1.txt" &
  pids+=($!)
  "${OUT_DIR}/l2_thrash" "${THRASH_MB}" "${DURATION}" >"${OUT_DIR}/${name}-thrash2.txt" &
  pids+=($!)

  sleep 3
  local p99
  p99="$(sample_lc)"
  echo "${p99}" > "${OUT_DIR}/${name}-lc-mean.txt"
  log "${name} lc_latency_mean_s=${p99}"

  # wait thrashers
  for p in "${pids[@]}"; do wait "${p}" || true; done

  curl -s 127.0.0.1:9103/metrics > "${OUT_DIR}/${name}-metrics.txt" || true
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root" >&2
    exit 1
  fi
  command -v cc >/dev/null || apt-get install -y -qq build-essential
  command -v python3 >/dev/null || apt-get install -y -qq python3
  build_thrash

  run_phase "unprotected" "observe"
  run_phase "advise" "advise"
  run_phase "enforce" "enforce"

  {
    echo "phase,lc_latency_mean_seconds"
    echo "unprotected,$(cat "${OUT_DIR}/unprotected-lc-mean.txt")"
    echo "advise,$(cat "${OUT_DIR}/advise-lc-mean.txt")"
    echo "enforce,$(cat "${OUT_DIR}/enforce-lc-mean.txt")"
  } > "${OUT_DIR}/summary.csv"

  echo "=== BASELINE SUMMARY ==="
  cat "${OUT_DIR}/summary.csv"
  echo "OUT_DIR=${OUT_DIR}"
  echo "VERDICT=BASELINE_COMPLETE"
}

main "$@"
