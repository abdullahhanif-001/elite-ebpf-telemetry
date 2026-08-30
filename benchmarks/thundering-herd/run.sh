#!/usr/bin/env bash
# Thundering herd v2 — conntrack + app RSS under spike (eth0 staging or lo safe).
set -euo pipefail
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${BUILD_ROOT}/logs"
OUT="${LOG_DIR}/thundering-herd-bench-latest.txt"
SPIKE="${TH_SPIKE_CONN:-5000}"
DUR="${TH_DUR_SEC:-10}"
TARGET_PORT="${TH_TARGET_PORT:-9}"
APP_PID_FILE="${TH_APP_PID_FILE:-}"

mkdir -p "${LOG_DIR}"
exec > >(tee "${OUT}") 2>&1
echo "=== thundering-herd v2 spike=${SPIKE} dur=${DUR}s ==="

rss_kb() {
  local pid="$1"
  if [[ -n "${pid}" ]] && [[ -r "/proc/${pid}/status" ]]; then
    awk '/^VmRSS:/ {print $2; exit}' "/proc/${pid}/status"
    return
  fi
  pid="$(pgrep -f elite-agent 2>/dev/null | head -1 || true)"
  if [[ -n "${pid}" ]]; then
    awk '/^VmRSS:/ {print $2; exit}' "/proc/${pid}/status"
  else
    echo 0
  fi
}

conntrack_count() {
  if [[ -f /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    cat /proc/sys/net/netfilter/nf_conntrack_count
  else
    ss -tan 2>/dev/null | wc -l || echo 0
  fi
}

app_pid=""
if [[ -n "${APP_PID_FILE}" ]] && [[ -f "${APP_PID_FILE}" ]]; then
  app_pid="$(cat "${APP_PID_FILE}")"
fi

before_rss="$(rss_kb "${app_pid}")"
before_ct="$(conntrack_count)"
echo "rss_before_kb=${before_rss} conntrack_before=${before_ct}"

if command -v hping3 >/dev/null 2>&1; then
  timeout "${DUR}" hping3 -S -p "${TARGET_PORT}" -i u10000 -c "${SPIKE}" 127.0.0.1 2>/dev/null || true
else
  timeout "${DUR}" bash -c "for i in \$(seq 1 ${SPIKE}); do (echo >/dev/tcp/127.0.0.1/${TARGET_PORT}) & done; wait" 2>/dev/null || true
fi
sleep 2

after_rss="$(rss_kb "${app_pid}")"
after_ct="$(conntrack_count)"
echo "rss_after_kb=${after_rss} conntrack_after=${after_ct}"

rss_pct=100
if [[ "${before_rss}" -gt 0 ]]; then
  rss_pct=$((after_rss * 100 / before_rss))
fi
ct_pct=100
if [[ "${before_ct}" -gt 0 ]]; then
  ct_pct=$((after_ct * 100 / before_ct))
fi
echo "rss_pct=${rss_pct} conntrack_pct=${ct_pct}"

if [[ "${rss_pct}" -le 110 ]] && [[ "${ct_pct}" -le 150 ]]; then
  echo "THUNDERING_HERD_PASS rss_pct=${rss_pct} ct_pct=${ct_pct}"
  exit 0
fi
echo "THUNDERING_HERD_FAIL rss_pct=${rss_pct} ct_pct=${ct_pct}"
exit 1
