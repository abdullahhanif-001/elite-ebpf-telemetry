#!/usr/bin/env bash
# elite-pm2-uninstall-guard.sh — abort uninstall if any PM2 service drifted.
# Never stops/restarts/deletes PM2 apps. Read-only compare to baseline jlist.
set -euo pipefail

BASE="${1:?usage: $0 <baseline-pm2-jlist.json> [label]}"
LABEL="${2:-check}"
CUR="$(mktemp)"
trap 'rm -f "${CUR}"' EXIT

if ! command -v pm2 >/dev/null 2>&1; then
  echo "FAIL[${LABEL}]: pm2 not found" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL[${LABEL}]: python3 required" >&2
  exit 1
fi
if [[ ! -f "${BASE}" ]]; then
  echo "FAIL[${LABEL}]: baseline missing: ${BASE}" >&2
  exit 1
fi

pm2 jlist >"${CUR}"

python3 - "${BASE}" "${CUR}" "${LABEL}" <<'PY'
import json
import sys

base_path, cur_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
with open(base_path, encoding="utf-8") as f:
    base_list = json.load(f)
with open(cur_path, encoding="utf-8") as f:
    cur_list = json.load(f)

B = {a["name"]: a.get("pm2_env") or {} for a in base_list}
C = {a["name"]: a.get("pm2_env") or {} for a in cur_list}

if set(B) != set(C):
    print(f"FAIL[{label}]: PM2 name set changed {set(B) ^ set(C)}", file=sys.stderr)
    sys.exit(1)

# Apps excluded from restart_time drift (known unstable; never stop/restart them here).
SKIP_RESTART = {"rider-tracker-api"}

for n in B:
    st = C[n].get("status")
    if st != "online":
        print(f"FAIL[{label}]: {n} status={st}", file=sys.stderr)
        sys.exit(1)
    if n in SKIP_RESTART:
        print(f"PM2_GUARD_SKIP_RESTART[{label}] {n} (excluded from restart_time check)")
        continue
    br = int(B[n].get("restart_time") or 0)
    cr = int(C[n].get("restart_time") or 0)
    if cr > br:
        print(f"FAIL[{label}]: {n} restart_time increased {br} -> {cr}", file=sys.stderr)
        sys.exit(1)

print(f"PM2_GUARD_OK[{label}] apps={len(B)}")
PY
