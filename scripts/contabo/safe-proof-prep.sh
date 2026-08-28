#!/usr/bin/env bash
# safe-proof-prep.sh — PM2 baseline, unload eth0 XDP, attach SKB mitigator on lo only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFACE_LO="${ELITE_XDP_IFACE:-lo}"
IFACE_ETH="${ELITE_XDP_UNLOAD_IFACE:-eth0}"

mkdir -p /opt/elite/baseline /opt/elite-build/logs

if command -v pm2 >/dev/null 2>&1; then
  pm2 jlist > /opt/elite/baseline/pm2-before.json
  echo "PM2_BASELINE_CAPTURED"
fi

if [[ -f "${SCRIPT_DIR}/xdp-emergency-unload.sh" ]]; then
  ELITE_XDP_IFACE="${IFACE_ETH}" XDP_HEALTH_NO_UNLOAD=1 bash "${SCRIPT_DIR}/xdp-emergency-unload.sh" || true
fi

command -v xdp-loader >/dev/null 2>&1 && xdp-loader unload "${IFACE_ETH}" 2>/dev/null || true

export ELITE_XDP_IFACE="${IFACE_LO}" ELITE_XDP_MODE=skb ELITE_XDP_FORCE=1
if [[ -f "${SCRIPT_DIR}/xdp-attach.sh" ]]; then
  bash "${SCRIPT_DIR}/xdp-attach.sh" load || echo "XDP_LO_ATTACH_SKIP"
fi

# Pin policy map for forecaster sync + W4
POLICY_PIN="/sys/fs/bpf/elite/policy"
if [[ ! -e "${POLICY_PIN}" ]] && command -v bpftool >/dev/null 2>&1; then
  id="$(bpftool map show 2>/dev/null | grep elite_policy | head -1 | cut -d: -f1)"
  if [[ -n "${id}" ]]; then
    mkdir -p /sys/fs/bpf/elite
    bpftool map pin id "${id}" "${POLICY_PIN}" 2>/dev/null || true
  fi
fi

echo "SAFE_PROOF_PREP_OK iface_lo=${IFACE_LO} eth0_unloaded=${IFACE_ETH}"
