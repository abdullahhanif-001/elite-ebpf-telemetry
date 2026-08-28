#!/bin/bash
set -euo pipefail
BASELINE=/opt/elite/baseline/pm2-before.json
if [[ ! -f "$BASELINE" ]]; then
  echo "FAIL: baseline missing"
  exit 1
fi
RESTARTS=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
BASE_RESTARTS=$(jq '[.[].pm2_env.restart_time] | add' "$BASELINE")
ONLINE=$(pm2 jlist | jq '[.[].pm2_env.status] | all(. == "online")')
if [[ "$ONLINE" != "true" ]]; then
  echo "FAIL: PM2 not all online"
  exit 1
fi
if [[ "$RESTARTS" -gt "$BASE_RESTARTS" ]]; then
  echo "FAIL: PM2 restarts increased ($BASE_RESTARTS -> $RESTARTS)"
  exit 1
fi
echo "PM2_GUARD_OK"
