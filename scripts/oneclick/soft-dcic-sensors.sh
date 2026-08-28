#!/usr/bin/env bash
# Soft DCIC sensors — CPU PSI + optional perf miss count sample (guest-safe).
set -euo pipefail

echo "=== soft-dcic-sensors $(date -Is) ==="
if [[ -f /proc/pressure/cpu ]]; then
  echo "-- CPU PSI --"
  cat /proc/pressure/cpu
else
  echo "CPU PSI unavailable"
fi

if [[ -f /proc/pressure/memory ]]; then
  echo "-- Memory PSI --"
  cat /proc/pressure/memory
fi

if command -v perf >/dev/null 2>&1; then
  echo "-- perf (1s, best-effort) --"
  timeout 3 perf stat -a -e cycles,instructions,cache-misses sleep 1 2>&1 | tail -n 20 || echo "perf sample skipped"
else
  echo "perf not installed (optional)"
fi

if [[ -f /etc/elite/dcic-capability.json ]]; then
  echo "-- capability --"
  cat /etc/elite/dcic-capability.json
fi

curl -s --connect-timeout 2 127.0.0.1:9103/metrics 2>/dev/null | grep -E '^elite_dcic_' || echo "elite-dcic metrics not up"
