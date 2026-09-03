#!/bin/bash
# pm2-guard.sh — abort if PM2 drifted; rider-tracker-api restart drift excluded (never touch that app).
# Fresh VPS without PM2: exit 0 with PM2_GUARD_N/A_NO_PM2 (not PASS, not FAIL).
set -euo pipefail
BASELINE=/opt/elite/baseline/pm2-before.json
SKIP="rider-tracker-api"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "PM2_GUARD_N/A_NO_PM2"
  exit 0
fi

if [[ ! -f "$BASELINE" ]]; then
  # No co-resident baseline yet — capture empty/current snapshot and treat as N/A once.
  mkdir -p "$(dirname "$BASELINE")"
  if pm2 jlist >/dev/null 2>&1; then
    pm2 jlist >"$BASELINE" 2>/dev/null || echo '[]' >"$BASELINE"
    echo "PM2_GUARD_N/A_BASELINE_CREATED"
    exit 0
  fi
  echo "PM2_GUARD_N/A_NO_PM2"
  exit 0
fi

ONLINE=$(pm2 jlist | jq '[.[].pm2_env.status] | all(. == "online")')
if [[ "$ONLINE" != "true" ]]; then
  # Empty PM2 list → all([]) is vacuously true in jq; non-true means apps offline.
  COUNT=$(pm2 jlist | jq 'length')
  if [[ "${COUNT}" -eq 0 ]]; then
    echo "PM2_GUARD_N/A_NO_APPS"
    exit 0
  fi
  echo "FAIL: PM2 not all online"
  exit 1
fi
python3 - "$BASELINE" "$SKIP" <<'PY'
import json, subprocess, sys
base_path, skip = sys.argv[1], sys.argv[2]
with open(base_path) as f:
    raw = json.load(f)
if not raw:
    print("PM2_GUARD_N/A_NO_APPS")
    sys.exit(0)
base = {a["name"]: int((a.get("pm2_env") or {}).get("restart_time") or 0) for a in raw}
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
