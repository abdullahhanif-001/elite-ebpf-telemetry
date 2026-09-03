#!/usr/bin/env bash
# xdp-emergency-unload.sh — recover SSH if XDP mitigator dropped traffic (fault=1 on eth0).
set -euo pipefail
IFACE="${ELITE_XDP_IFACE:-eth0}"
POLICY_PIN="${ELITE_POLICY_PIN:-/sys/fs/bpf/elite/policy}"
echo "Emergency: unload XDP on ${IFACE} and clear policy fault"
command -v xdp-loader >/dev/null 2>&1 && xdp-loader unload "${IFACE}" || true
if [[ -e "${POLICY_PIN}" ]] && command -v bpftool >/dev/null 2>&1; then
  bpftool map update pinned "${POLICY_PIN}" key hex 00 00 00 00 \
    value hex 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2>/dev/null || true
fi
echo "XDP_EMERGENCY_DONE"
