#!/usr/bin/env bash
# Recover agent + baseline after stress abort; run xray, gates, speed, stress.
set -uo pipefail
export REAL_ONLY=1 SKIP_PHYSICS_PROOF=1
export ELITE_BUILD_ROOT=/opt/elite-build ELITE_SRC=/opt/elite/src
D=/opt/elite/src/scripts/oneclick

bash /opt/elite/src/scripts/server/safe-proof-prep.sh

systemctl start elite-agent
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:9102/metrics >/dev/null 2>&1; then
    echo "AGENT_METRICS_READY attempt=$i"
    break
  fi
  sleep 2
done

sleep 45
bash "$D/competitive-speed-proof.sh" || true

xdp-loader unload eth0 2>/dev/null || true
export ELITE_XDP_IFACE=eth0 ELITE_XDP_MODE=skb ELITE_XDP_FORCE=1
bash /opt/elite/src/scripts/server/xdp-attach.sh load || true
id=$(bpftool map show 2>/dev/null | grep elite_policy | head -1 | cut -d: -f1)
if [ -n "$id" ]; then
  mkdir -p /sys/fs/bpf/elite
  bpftool map pin id "$id" /sys/fs/bpf/elite/policy 2>/dev/null || true
fi

bash /opt/elite/src/scripts/oneclick/ebpf-xray-real-proof.sh || true
xdp-loader unload eth0 2>/dev/null || true

bash /opt/elite/src/deploy/server/final-stress-test.sh || true
bash "$D/gates-checklist.sh" || true

pm2 jlist | jq '[.[].pm2_env.restart_time] | add' 2>/dev/null
echo "=== RECOVERY DONE ==="
