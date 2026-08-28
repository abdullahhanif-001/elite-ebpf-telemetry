#!/usr/bin/env bash
# Minimal elite_* metrics bridge on :9102 for Soft Track A when full BPF agent
# is not yet built. Proxies/aliases Soft DCIC + optional ebpf_exporter signals.
set -euo pipefail

LISTEN="${ELITE_BRIDGE_LISTEN:-127.0.0.1:9102}"
export ELITE_BRIDGE_LISTEN="${LISTEN}"
export DCIC_METRICS_URL="${DCIC_METRICS_URL:-http://127.0.0.1:9103/metrics}"
export EBPF_EXPORTER_URL="${EBPF_EXPORTER_URL:-http://127.0.0.1:9435/metrics}"

python3 - <<'PY' &
import http.server, urllib.request, socketserver, os, re

LISTEN = os.environ.get("ELITE_BRIDGE_LISTEN", "127.0.0.1:9102")
host, port = LISTEN.split(":")
port = int(port)
DCIC = os.environ.get("DCIC_METRICS_URL", "http://127.0.0.1:9103/metrics")
EXP = os.environ.get("EBPF_EXPORTER_URL", "http://127.0.0.1:9435/metrics")

def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return ""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/healthz"):
            self.send_response(404); self.end_headers(); return
        if self.path == "/healthz":
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok\n"); return
        body = []
        body.append("# Elite Soft Track A metrics bridge\n")
        dcic = fetch(DCIC)
        for line in dcic.splitlines():
            if line.startswith("elite_dcic_lc_latency_seconds"):
                val = line.split()[-1]
                body.append("# HELP elite_socketlatency_seconds Soft-bridge LC latency alias\n")
                body.append("# TYPE elite_socketlatency_seconds gauge\n")
                body.append(f"elite_socketlatency_seconds {val}\n")
            if line.startswith("elite_"):
                body.append(line + "\n")
        exp = fetch(EXP)
        for line in exp.splitlines():
            if line.startswith("softirq_wait_seconds"):
                # export as elite_softirq alias for forecaster compatibility
                val = line.split()[-1] if line.split() else "0"
                body.append("# HELP elite_softirq_wait_seconds Bridged softirq wait\n")
                body.append("# TYPE elite_softirq_wait_seconds gauge\n")
                body.append(f"elite_softirq_wait_seconds {val}\n")
                break
        data = "".join(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

with socketserver.TCPServer((host, port), H) as httpd:
    httpd.serve_forever()
PY
BRIDGE_PID=$!
echo "${BRIDGE_PID}" > /run/elite-metrics-bridge.pid
echo "elite-metrics-bridge pid=${BRIDGE_PID} on ${LISTEN}"
