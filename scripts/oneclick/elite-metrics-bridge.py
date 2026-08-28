#!/usr/bin/env python3
"""Elite Soft Track A metrics bridge — elite_* on :9102 without full BPF agent."""
import http.server
import os
import socketserver
import urllib.request

LISTEN = os.environ.get("ELITE_BRIDGE_LISTEN", "127.0.0.1:9102")
host, port_s = LISTEN.split(":")
PORT = int(port_s)
DCIC = os.environ.get("DCIC_METRICS_URL", "http://127.0.0.1:9103/metrics")
EXP = os.environ.get("EBPF_EXPORTER_URL", "http://127.0.0.1:9435/metrics")


def fetch(url: str) -> str:
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return ""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        parts = ["# Elite Soft Track A metrics bridge\n"]
        dcic = fetch(DCIC)
        for line in dcic.splitlines():
            if line.startswith("elite_dcic_lc_latency_seconds"):
                val = line.split()[-1]
                parts.append("# HELP elite_socketlatency_seconds Soft-bridge LC latency alias\n")
                parts.append("# TYPE elite_socketlatency_seconds gauge\n")
                parts.append(f"elite_socketlatency_seconds {val}\n")
            if line.startswith("elite_"):
                parts.append(line + "\n")
        for line in fetch(EXP).splitlines():
            if line.startswith("softirq_wait_seconds"):
                val = line.split()[-1]
                parts.append("# HELP elite_softirq_wait_seconds Bridged softirq wait\n")
                parts.append("# TYPE elite_softirq_wait_seconds gauge\n")
                parts.append(f"elite_softirq_wait_seconds {val}\n")
                break
        data = "".join(parts).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):  # noqa: A003
        return


if __name__ == "__main__":
    with socketserver.TCPServer((host, PORT), Handler) as httpd:
        httpd.serve_forever()
