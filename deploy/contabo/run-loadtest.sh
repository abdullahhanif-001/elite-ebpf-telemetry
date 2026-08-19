#!/usr/bin/env bash
# k6 load test with PM2 watchdog — Contabo safe deploy
set -euo pipefail

TARGET="${TARGET:-http://127.0.0.1:3001/}"
VUS="${VUS:-30}"
DURATION="${DURATION:-60s}"
RESULTS="/opt/elite/baseline/loadtest-$(date +%Y%m%d-%H%M%S).txt"

mkdir -p /opt/elite/baseline

echo "== Load test: $TARGET ${VUS}VUs $DURATION ==" | tee "$RESULTS"

bash /opt/elite/scripts/pm2-guard.sh | tee -a "$RESULTS"

# Snapshot PM2 CPU before
pm2 jlist | jq '[.[].monit.cpu] | add' > /tmp/pm2-cpu-before.txt
echo "pm2_cpu_before=$(cat /tmp/pm2-cpu-before.txt)" | tee -a "$RESULTS"

# Snapshot elite-agent CPU before
systemctl show elite-agent -p CPUUsageNSec,MemoryCurrent | tee -a "$RESULTS"

# Background PM2 watchdog — stop elite if PM2 degrades
(
  while true; do
    if ! bash /opt/elite/scripts/pm2-guard.sh >/dev/null 2>&1; then
      echo "WATCHDOG: PM2 guard failed — stopping elite-agent" | tee -a "$RESULTS"
      systemctl stop elite-agent
      exit 1
    fi
    sleep 2
  done
) &
WATCHDOG_PID=$!
trap "kill $WATCHDOG_PID 2>/dev/null || true" EXIT

docker pull grafana/k6:latest >/dev/null 2>&1 || true

docker run --rm --network host \
  -v /opt/elite/scripts/load.js:/scripts/load.js:ro \
  -e TARGET_URL="$TARGET" \
  grafana/k6:latest run \
  --vus "$VUS" --duration "$DURATION" /scripts/load.js \
  2>&1 | tee -a "$RESULTS"

kill $WATCHDOG_PID 2>/dev/null || true
trap - EXIT

# Post-checks
pm2 jlist | jq '[.[].monit.cpu] | add' > /tmp/pm2-cpu-after.txt
cpu_before=$(cat /tmp/pm2-cpu-before.txt)
cpu_after=$(cat /tmp/pm2-cpu-after.txt)
cpu_delta=$(awk "BEGIN {printf \"%.1f\", $cpu_after - $cpu_before}")

echo "pm2_cpu_after=$cpu_after pm2_cpu_delta=$cpu_delta" | tee -a "$RESULTS"
systemctl show elite-agent -p CPUUsageNSec,MemoryCurrent | tee -a "$RESULTS"
bash /opt/elite/scripts/pm2-guard.sh | tee -a "$RESULTS"

# Pass criteria from plan
if awk "BEGIN {exit !($cpu_delta < 2)}"; then
  echo "PASS: PM2 CPU delta ${cpu_delta}% (<2% aggregate threshold)" | tee -a "$RESULTS"
else
  echo "WARN: PM2 CPU delta ${cpu_delta}% elevated" | tee -a "$RESULTS"
fi

curl -sf -o /dev/null -w "nginx_80=%{http_code}\n" http://127.0.0.1:80/ | tee -a "$RESULTS" || echo "nginx_80=fail" | tee -a "$RESULTS"

echo "Results saved: $RESULTS"
