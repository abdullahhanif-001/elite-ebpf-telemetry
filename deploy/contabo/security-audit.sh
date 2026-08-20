#!/usr/bin/env bash
# Security audit harness — PM2-safe (never touches pm2/node)
set -euo pipefail

OUT="/opt/elite/baseline/security-audit-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$OUT") 2>&1

echo "=== ELITE SECURITY AUDIT $(date -Is) ==="
echo "LOG=$OUT"

guard() {
  bash /opt/elite/scripts/pm2-guard.sh
}

echo "--- PM2 baseline ---"
guard
pm2 jlist | jq '[.[].name, .[].pm2_env.status, .[].pm2_env.restart_time] | {names: .[0:6], status: .[6:12], restarts: .[12:18]}'

BASE_RESTARTS=$(jq '[.[].pm2_env.restart_time] | add' /opt/elite/baseline/pm2-before.json)

echo "--- Attack surface: HTTP :9102 ---"
for path in /metrics /status /debug/pprof/ /debug/pprof/heap /internal; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:9102${path}" 2>/dev/null || echo "000")
  echo "GET ${path} -> ${code}"
done

echo "--- Fuzz: malformed HTTP headers ---"
python3 - <<'PY'
import socket
s = socket.create_connection(("127.0.0.1", 9102), timeout=3)
s.sendall(b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Inject: " + b"A"*8192 + b"\r\n\r\n")
print(s.recv(256).split(b"\r\n")[0].decode(errors="replace"))
s.close()
PY

echo "--- Metrics latency p50/p99 (100 samples) ---"
python3 - <<'PY'
import time, urllib.request, statistics
lat=[]
for _ in range(100):
    t0=time.perf_counter_ns()
    urllib.request.urlopen("http://127.0.0.1:9102/metrics", timeout=5)
    lat.append(time.perf_counter_ns()-t0)
lat.sort()
print(f"p50_ns={lat[49]} p99_ns={lat[98]} max_ns={lat[-1]}")
PY

echo "--- elite-agent resource snapshot ---"
systemctl show elite-agent -p ActiveState,CPUUsageNSec,MemoryCurrent,CPUQuota,MemoryMax

echo "--- Prometheus scrape health ---"
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up{job="elite-agent"}' | jq -r '.data.result[0].value[1] // "missing"' || echo "missing"

echo "--- Metric prefix inventory ---"
curl -sf http://127.0.0.1:9102/metrics | grep -oE '^elite_[a-z_]+' | sort -u | head -20

echo "--- Port exposure (must be 127.0.0.1 only) ---"
ss -tlnp | grep -E '9102|9090|3030' || true

echo "--- systemd hardening flags ---"
systemctl show elite-agent -p NoNewPrivileges,CapabilityBoundingSet,MemoryMax,CPUQuota,ProtectSystem

echo "--- PM2 post-audit ---"
guard
AFTER=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
echo "restarts_before=$BASE_RESTARTS restarts_after=$AFTER"
if [ "$AFTER" -gt "$BASE_RESTARTS" ]; then
  echo "FAIL: PM2 restart count increased"
  exit 1
fi
echo "PM2_ZERO_EFFECT=PASS"
echo "=== AUDIT COMPLETE ==="
