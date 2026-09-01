#!/bin/bash
# pm2-guard.sh — abort if PM2 drifted; rider-tracker-api restart drift excluded (never touch that app).
set -euo pipefail
BASELINE=/opt/elite/baseline/pm2-before.json
SKIP="rider-tracker-api"
if [[ ! -f "$BASELINE" ]]; then
  echo "FAIL: baseline missing"
  exit 1
fi
ONLINE=$(pm2 jlist | jq '[.[].pm2_env.status] | all(. == "online")')
if [[ "$ONLINE" != "true" ]]; then
  echo "FAIL: PM2 not all online"
  exit 1
fi
python3 - "$BASELINE" "$SKIP" <<'PY'
import json, subprocess, sys
base_path, skip = sys.argv[1], sys.argv[2]
with open(base_path) as f:
    base = {a["name"]: int((a.get("pm2_env") or {}).get("restart_time") or 0) for a in json.load(f)}
cur = json.loads(subprocess.check_output(["pm2", "jlist"], text=True))
cur = {a["name"]: int((a.get("pm2_env") or {}).get("restart_time") or 0) for a in cur}
for n in base:
    if n == skip:
        print(f"PM2_GUARD_SKIP_RESTART {n} base={base[n]} cur={cur.get(n,0)}")
        continue
    if cur.get(n, 0) > base[n]:
        print(f"FAIL: {n} restart_time {base[n]} -> {cur[n]}", file=sys.stderr)
        sys.exit(1)
print("PM2_GUARD_OK")
PY
