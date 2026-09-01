#!/usr/bin/env bash
# tier3-run-all.sh — run all 6 schedulers (simple loop on VPS).
set -euo pipefail
pkill -9 -f '/opt/scx/target/release/scx_' 2>/dev/null || true
sleep 2
G="${ELITE_SRC:-/opt/elite/src}/benchmarks/ebpf-gates/tier3-simple.sh"
for s in bpfland lavd rusty flash rustland; do
  echo "--- $s ---"
  bash "$G" "$s" || true
  sleep 20
done
echo "--- layered ---"
bash "${ELITE_SRC:-/opt/elite/src}/benchmarks/ebpf-gates/tier3-layered-simple.sh" || true
sleep 20
echo "TIER3_RUN_ALL_DONE"
