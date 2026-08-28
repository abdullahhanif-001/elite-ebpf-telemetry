#!/usr/bin/env bash
# Sherlock-style adversarial audit — wraps security-audit + extra attack probes.
# PM2-safe: never touches pm2/node processes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="/opt/elite/baseline/adversarial-audit-$(date +%Y%m%d-%H%M%S).log"
FAIL=0

exec > >(tee "$OUT") 2>&1
echo "=== ELITE ADVERSARIAL AUDIT $(date -Is) ==="

BASE_RESTARTS=$(jq '[.[].pm2_env.restart_time] | add' /opt/elite/baseline/pm2-before.json 2>/dev/null || echo "0")

record() {
  local id="$1" sev="$2" msg="$3"
  if [[ "$4" = "PASS" ]]; then
    echo "[$id][$sev] PASS: $msg"
  else
    echo "[$id][$sev] FAIL: $msg"
    FAIL=$((FAIL + 1))
  fi
}

bash "$ROOT/security-audit.sh" || true

echo "--- A-01 Critical: unauthenticated debug endpoints ---"
for path in /debug/pprof/ /debug/pprof/heap /status; do
  code=$(curl -sf -o /dev/null -w '%{http_code}' "http://127.0.0.1:9102${path}" 2>/dev/null || echo "000")
  if [[ "$path" = "/status" ]]; then
    # /status may be 404 when debugMode=false (acceptable)
    if [[ "$code" = "200" ]]; then
      record A-01 Critical "GET ${path} returned 200 without auth" FAIL
    else
      record A-01 Critical "GET ${path} -> ${code}" PASS
    fi
  else
    if [[ "$code" = "200" ]]; then
      record A-01 Critical "GET ${path} returned 200" FAIL
    else
      record A-01 Critical "GET ${path} -> ${code}" PASS
    fi
  fi
done

echo "--- A-03 High: slowloris partial request ---"
python3 - <<'PY'
import socket, time
s = socket.create_connection(("127.0.0.1", 9102), timeout=3)
s.sendall(b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\n")
time.sleep(2)
s.sendall(b"\r\n")
resp = s.recv(128)
s.close()
print(resp.split(b"\r\n")[0].decode(errors="replace"))
PY

echo "--- A-04 High: oversized header fuzz (>1MB, expect reject) ---"
FUZZ_LINE=$(python3 - <<'PY'
import socket
s = socket.create_connection(("127.0.0.1", 9102), timeout=5)
s.sendall(b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Big: " + b"B"*(2*1024*1024) + b"\r\n\r\n")
try:
    line = s.recv(256).split(b"\r\n")[0].decode(errors="replace")
except Exception:
    line = "CONNECTION_CLOSED"
s.close()
print(line)
PY
)
echo "fuzz_response=$FUZZ_LINE"
if echo "$FUZZ_LINE" | grep -qE "HTTP/1.1 (200|301|302)"; then
  record A-04 High "oversized header accepted with success status" FAIL
else
  record A-04 High "oversized header rejected ($FUZZ_LINE)" PASS
fi
if curl -sf -o /dev/null http://127.0.0.1:9102/metrics; then
  record A-04b High "metrics healthy after fuzz" PASS
else
  record A-04b High "metrics down after fuzz" FAIL
fi

echo "--- A-05 High: metrics non-empty ---"
COUNT=$(curl -sf http://127.0.0.1:9102/metrics 2>/dev/null | grep -cE '^elite_' || echo 0)
if [[ "$COUNT" -lt 5 ]]; then
  record A-05 High "fewer than 5 metric lines (got $COUNT)" FAIL
else
  record A-05 High "metric series present ($COUNT lines)" PASS
fi

echo "--- A-06 bind check: localhost only ---"
if ss -tln | grep ':9102' | grep -qv '127.0.0.1:9102'; then
  record A-02 Critical "9102 bound beyond localhost" FAIL
else
  record A-02 Critical "9102 localhost-only" PASS
fi

echo "--- PM2 guard final ---"
bash /opt/elite/scripts/pm2-guard.sh
AFTER=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
if [[ "$AFTER" -gt "$BASE_RESTARTS" ]]; then
  record PM2 Critical "restarts increased $BASE_RESTARTS -> $AFTER" FAIL
else
  record PM2 Critical "restarts unchanged ($AFTER)" PASS
fi

echo "--- Physics Pack exporters (if installed) ---"
if [[ "${SKIP_PHYSICS_PROOF:-0}" == "1" ]] || [[ "${REAL_ONLY:-0}" == "1" ]]; then
  echo "SKIP_PHYSICS_PROOF: native :9102 path — skip ebpf_exporter :9435 proof"
else
PACK_PROOF="$(cd "$(dirname "$0")" && pwd)/oneclick/physics-pack-proof.sh"
if [[ -f "$PACK_PROOF" ]]; then
  if ! bash "$PACK_PROOF"; then
    FAIL=$((FAIL + 1))
  fi
else
  echo "physics-pack-proof.sh not found; skip"
fi
fi

echo "=== ADVERSARIAL AUDIT FAILURES=$FAIL LOG=$OUT ==="
exit "$FAIL"
