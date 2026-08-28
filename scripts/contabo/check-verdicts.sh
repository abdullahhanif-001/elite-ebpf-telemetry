#!/usr/bin/env bash
set -uo pipefail
echo "=== VERDICT SUMMARY ==="
ls -td /opt/elite/src/scripts/oneclick/results/ebpf-xray-* 2>/dev/null | head -1 | while read d; do
  echo "XRAY_DIR=$d"
  cat "$d/xray.log" 2>/dev/null || echo "no xray.log"
  cat "$d/verdict.txt" 2>/dev/null || echo "no verdict"
done
ls -td /tmp/elite-speed-* 2>/dev/null | head -1 | while read d; do
  echo "SPEED_DIR=$d"
  tail -3 "$d/summary.txt" 2>/dev/null || tail -5 "$d"/*.log 2>/dev/null
done
grep -h VERDICT /opt/elite/src/scripts/oneclick/*.md 2>/dev/null | tail -5
test -f /opt/elite/FINAL_STRESS_TEST.log && tail -3 /opt/elite/FINAL_STRESS_TEST.log
systemctl is-active elite-agent
curl -s -o /dev/null -w "agent_http=%{http_code}\n" http://127.0.0.1:9102/metrics
