#!/usr/bin/env bash
set -euo pipefail

echo "=== PM2 baseline ==="
pm2 jlist | jq '[.[].pm2_env.restart_time] | add'
pm2 jlist | jq -r '.[] | "\(.name) \(.pm2_env.status) restarts=\(.pm2_env.restart_time)"'

echo "=== Deploy new elite-agent ==="
systemctl stop elite-agent
cp -a /opt/elite/bin/elite-agent "/opt/elite/bin/elite-agent.bak-$(date +%Y%m%d%H%M%S)"
install -m 0755 /opt/elite/src/bin/elite-agent /opt/elite/bin/elite-agent
systemctl start elite-agent
sleep 8
systemctl is-active elite-agent
journalctl -u elite-agent -n 30 --no-pager

echo "=== Metrics ==="
curl -sf http://127.0.0.1:9102/metrics | grep -E '^elite_|HELP elite' | head -20 || true
curl -sf -o /dev/null -w "metrics_http=%{http_code}\n" http://127.0.0.1:9102/metrics
code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9102/debug/pprof/ || true)
echo "pprof_http=${code}"

echo "=== PM2 after ==="
pm2 jlist | jq '[.[].pm2_env.restart_time] | add'
pm2 jlist | jq -r '.[] | select(.pm2_env.status != "online") | .name' | wc -l

if [[ -x /opt/elite/src/scripts/elite-adversarial-audit.sh ]]; then
  bash /opt/elite/src/scripts/elite-adversarial-audit.sh || true
fi
if [[ -x /opt/elite/src/deploy/contabo/security-audit.sh ]]; then
  bash /opt/elite/src/deploy/contabo/security-audit.sh || true
fi
if [[ -x /opt/elite/scripts/pm2-guard.sh ]]; then
  bash /opt/elite/scripts/pm2-guard.sh || true
fi

echo DEPLOY_AUDIT_DONE
