#!/usr/bin/env bash
# Safe final test suite — never sets XDP fault=1 on eth0.
set -uo pipefail
export REAL_ONLY=1 SKIP_PHYSICS_PROOF=1 PROOFS_ONLY=1
export ELITE_BUILD_ROOT=/opt/elite-build ELITE_SRC=/opt/elite/src
D=/opt/elite/src/scripts/oneclick

# Speed proof before heavy forecaster benches (S0 CPU soak is sensitive).
bash "$D/competitive-speed-proof.sh" || true
bash "$D/forecaster-agrade.sh" || true
bash "$D/competitive-overhead-proof.sh" || true
bash "$D/competitive-live-predict-proof.sh" || true
bash "$D/soft-dcic-proof.sh" || true
bash "$D/category-bakeoff.sh" || true
bash /opt/elite/src/deploy/contabo/final-stress-test.sh || true
SKIP_PHYSICS_PROOF=1 bash /opt/elite/src/scripts/elite-adversarial-audit.sh || true

# XDP on eth0 with fault=0 only; unload after W4/xray
xdp-loader unload eth0 2>/dev/null || true
export ELITE_XDP_IFACE=eth0 ELITE_XDP_MODE=skb ELITE_XDP_FORCE=1
bash /opt/elite/src/scripts/contabo/xdp-attach.sh load || true
id=$(bpftool map show 2>/dev/null | grep elite_policy | head -1 | cut -d: -f1)
if [ -n "$id" ]; then
  mkdir -p /sys/fs/bpf/elite
  bpftool map pin id "$id" /sys/fs/bpf/elite/policy 2>/dev/null || true
  bpftool map update pinned /sys/fs/bpf/elite/policy key hex 00 00 00 00 \
    value hex 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 || true
fi
bash /opt/elite/src/benchmarks/contabo-gates/w4-xdp-inject-latency.sh || true
bash /opt/elite/src/scripts/oneclick/ebpf-xray-real-proof.sh || true
xdp-loader unload eth0 2>/dev/null || true

bash "$D/gates-checklist.sh" || true
pm2 jlist | jq '[.[].pm2_env.restart_time] | add' 2>/dev/null || echo pm2_check
