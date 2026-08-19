#!/usr/bin/env bash
# k6 load test wrapper — delegates to bare-metal script when present
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/deploy/contabo/run-loadtest.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: $SCRIPT not found. Copy deploy/contabo/ to the host first." >&2
  exit 1
fi

echo "Note: run pm2-guard.sh before load tests on hosts with PM2 apps."
exec bash "$SCRIPT" "$@"
