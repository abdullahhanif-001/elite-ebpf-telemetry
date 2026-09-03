#!/usr/bin/env bash
# Elite agent overhead benchmark — systemd mode (no kubectl)
set -euo pipefail

DURATION="${BENCH_DURATION:-60}"
THRESHOLD="${CPU_THRESHOLD:-0.10}"
INTERVAL=5

echo "== Elite overhead benchmark (${DURATION}s, systemd) =="

if ! systemctl is-active --quiet elite-agent; then
  echo "FAIL: elite-agent not running"
  exit 1
fi

samples=()
end=$((SECONDS + DURATION))
while [[ $SECONDS -lt $end ]]; do
  cpu_nsec=$(systemctl show elite-agent -p CPUUsageNSec --value)
  samples+=("$cpu_nsec")
  sleep "$INTERVAL"
done

# Delta CPUUsageNSec over window / duration = avg nsec/sec = fraction of 1 core
first=${samples[0]}
last=${samples[-1]}
delta=$((last - first))
cores=$(awk "BEGIN {printf \"%.4f\", ($delta / 1e9) / $DURATION}")
mem=$(systemctl show elite-agent -p MemoryCurrent --value)

echo "cpu_cores_avg=$cores mem_bytes=$mem threshold=$THRESHOLD"

if awk "BEGIN {exit !($cores < $THRESHOLD)}"; then
  echo "PASS: elite_agent_cpu_cores=$cores (<$THRESHOLD)"
  exit 0
else
  echo "FAIL: elite_agent_cpu_cores=$cores (>=$THRESHOLD)"
  exit 1
fi
