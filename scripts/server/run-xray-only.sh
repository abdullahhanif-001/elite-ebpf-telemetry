#!/usr/bin/env bash
set -uo pipefail
xdp-loader unload eth0 2>/dev/null || true
export ELITE_XDP_IFACE=eth0 ELITE_XDP_MODE=skb ELITE_XDP_FORCE=1
bash /opt/elite/src/scripts/server/xdp-attach.sh load || true
bash /opt/elite/src/scripts/oneclick/ebpf-xray-real-proof.sh
xdp-loader unload eth0 2>/dev/null || true
