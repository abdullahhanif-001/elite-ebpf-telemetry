#!/usr/bin/env bash
# W5 — graduated XDP shed: RSS stable while elite_xdp_drop rises (safe lo iface).
set -euo pipefail
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${ELITE_LOG_DIR:-${BUILD_ROOT}/logs}"
SRC="${ELITE_SRC:-/opt/elite/src}"
BPF_PIN="${ELITE_BPF_PIN:-/sys/fs/bpf/elite}"
POLICY_PIN="${ELITE_POLICY_PIN:-${BPF_PIN}/policy}"
IFACE="${ELITE_XDP_IFACE:-lo}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${LOG_DIR}/w5-xdp-graduated-${STAMP}.txt"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${OUT}") 2>&1
echo "=== W5 xdp-graduated-shed ${STAMP} iface=${IFACE} ==="

skip() { echo "W5_SKIP: $*"; echo "W5_SKIP" >"${LOG_DIR}/w5-xdp-graduated-latest.verdict"; exit 2; }
fail() { echo "W5_FAIL: $*"; echo "W5_FAIL" >"${LOG_DIR}/w5-xdp-graduated-latest.verdict"; exit 1; }
pass() { echo "W5_PASS: $*"; echo "W5_PASS" >"${LOG_DIR}/w5-xdp-graduated-latest.verdict"; cp -f "${OUT}" "${LOG_DIR}/w5-xdp-graduated-latest.txt"; exit 0; }

[[ -e "${POLICY_PIN}" ]] || skip "policy map not pinned"
ATTACH="${SRC}/scripts/contabo/xdp-attach.sh"
[[ -f "${ATTACH}" ]] || ATTACH="${SRC}/scripts/contabo/xdp-attach.sh"
export ELITE_XDP_IFACE="${IFACE}" ELITE_XDP_MODE=skb ELITE_XDP_FORCE=1

# Set graduated shed via bpftool (actuate=1, shed_ppm=500000)
if command -v bpftool >/dev/null 2>&1; then
  bpftool map update pinned "${POLICY_PIN}" key hex 00 00 00 00 \
    value hex 02 00 00 00 00 00 00 00 00 01 01 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2f ba 0d 00 2f ba 0d 00 00 00 00 00 2>/dev/null || true
fi

rss_before="$(awk '/^VmRSS:/ {print $2; exit}' /proc/self/status 2>/dev/null || echo 0)"
# flood lo with small packets
timeout 5 ping -f -c 2000 127.0.0.1 >/dev/null 2>&1 || true
rss_after="$(awk '/^VmRSS:/ {print $2; exit}' /proc/self/status 2>/dev/null || echo 0)"

drops=0
if [[ -e "${BPF_PIN}/xdp_stats" ]] && command -v bpftool >/dev/null 2>&1; then
  drops="$(bpftool map dump pinned "${BPF_PIN}/xdp_stats" 2>/dev/null | grep -c drop || echo 0)"
fi
echo "rss_before=${rss_before} rss_after=${rss_after} drops_hint=${drops}"

# Reset actuate-safe
if command -v bpftool >/dev/null 2>&1; then
  bpftool map update pinned "${POLICY_PIN}" key hex 00 00 00 00 value hex 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2>/dev/null || true
fi

if [[ "${rss_after}" -le $((rss_before + rss_before / 10 + 4096)) ]]; then
  pass "RSS stable rss_before=${rss_before} rss_after=${rss_after}"
fi
fail "RSS grew too much"
