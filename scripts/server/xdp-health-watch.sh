#!/usr/bin/env bash
# xdp-health-watch.sh — P2.7 post-attach connectivity + metrics health.
set -euo pipefail

IFACE="${ELITE_XDP_IFACE:-eth0}"
AGENT_URL="${AGENT_URL:-http://127.0.0.1:9102/metrics}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "XDP_HEALTH_FAIL: $*"
  if [[ "${XDP_HEALTH_NO_UNLOAD:-0}" != "1" ]] && [[ -x "${SCRIPT_DIR}/xdp-attach.sh" ]]; then
    ELITE_XDP_IFACE="${IFACE}" bash "${SCRIPT_DIR}/xdp-attach.sh" unload || true
  fi
  exit 1
}

ready=0
for wait in 1 2 3 5 8 10; do
  if curl -fsS --max-time 5 "${AGENT_URL}" | head -1 >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep "${wait}"
done
[[ "${ready}" -eq 1 ]] || fail "agent metrics unreachable at ${AGENT_URL}"

if command -v ip >/dev/null 2>&1; then
  ip route get 1.1.1.1 >/dev/null 2>&1 || fail "default route probe failed"
fi

echo "XDP_HEALTH_OK iface=${IFACE}"
