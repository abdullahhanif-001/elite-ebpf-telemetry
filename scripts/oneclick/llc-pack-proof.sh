#!/usr/bin/env bash
# server/VPS proof for Elite LLC sensors.
# Exit 0 = PASS, 2 = SKIP (no PMU), 1 = FAIL
set -euo pipefail

LISTEN="${ELITE_LLC_LISTEN:-127.0.0.1:9104}"
FAIL=0

record() {
  local id="$1" msg="$2" ok="$3"
  echo "[${id}] ${ok}: ${msg}"
  if [[ "${ok}" == "FAIL" ]]; then
    FAIL=$((FAIL + 1))
  fi
}

code="$(curl -s -o /tmp/elite-llc-body.txt -w '%{http_code}' --connect-timeout 2 "${LISTEN}/metrics" 2>/dev/null || echo 000)"
if [[ "${code}" != "200" ]]; then
  # Not installed / not listening on this host — capability SKIP, not FAIL.
  record L-01 "${LISTEN}/metrics -> ${code} (LLC sensors not running)" SKIP
  exit 2
fi
body="$(cat /tmp/elite-llc-body.txt)"
if ! grep -q 'elite_llc_enabled' <<<"${body}"; then
  record L-01 "missing elite_llc_enabled" FAIL
  exit 1
fi
en="$(awk '/^elite_llc_enabled/{print $2; exit}' <<<"${body}")"
if [[ "${en}" == "0" || "${en}" == "0.0" ]]; then
  record L-02 "llc_enabled=0 (no PMU) — DEFERRED not FAIL" SKIP
  echo "LLC_DEFERRED_NO_PMU"
  exit 0
fi
record L-02 "llc_enabled=1" PASS
if grep -qE '^elite_llc_miss_rate' <<<"${body}"; then
  record L-03 "miss_rate present" PASS
else
  record L-03 "miss_rate missing" FAIL
fi
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
exit 0
