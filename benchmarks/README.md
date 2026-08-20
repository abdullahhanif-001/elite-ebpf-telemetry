# Elite Benchmark Suite

Professional overhead and load benchmarks for the Elite eBPF agent.

## Purpose

Measure agent CPU and memory overhead under idle and load, without modifying application code. Supports Kubernetes (DaemonSet) and bare-metal (systemd) deployments.

## Prerequisites

| Mode | Requirements |
|------|----------------|
| Kubernetes | `kubectl`, cluster access, Elite in `elite` namespace |
| systemd | Linux, `systemctl`, Elite running as `elite-agent.service` |
| Load test | Docker (for k6) or [k6](https://k6.io/) installed locally |

## Quick start

```bash
# CPU overhead — Kubernetes
./benchmarks/run-overhead.sh

# CPU overhead — systemd (VPS / bare metal)
./benchmarks/run-overhead.sh --mode systemd

# Load test (bare metal, PM2-safe — uses localhost closed port)
TARGET=http://127.0.0.1:3001/ ./benchmarks/run-loadtest.sh
```

## SLO gates

| Metric | Target | Script |
|--------|--------|--------|
| Agent CPU overhead | < 1% core fraction (60s) | `run-overhead.sh` |
| RSS memory (systemd) | < 160 MB under load | `run-overhead-systemd.sh` |
| PM2 restart delta | 0 (bare metal) | `run-loadtest.sh` + `pm2-guard.sh` |
| Metric scrape p99 | < 500 ms | `run-loadtest.sh` (optional) |

## Expected output

```text
== Elite overhead benchmark (60s) ==
avg_cpu_millicores=8 ratio=0.0080 threshold=0.01
PASS: elite_agent_cpu_ratio=0.0080 (<0.01)
```

```text
== Elite overhead benchmark (30s, systemd) ==
cpu_cores_avg=0.0079 mem_bytes=88244224 threshold=0.10
PASS: elite_agent_cpu_cores=0.0079 (<0.10)
```

## Files

| File | Description |
|------|-------------|
| [BENCHMARKS.md](BENCHMARKS.md) | Methodology, sampling windows, kernel 6.8 notes |
| [run-overhead.sh](run-overhead.sh) | CPU overhead (K8s or `--mode systemd`) |
| [run-loadtest.sh](run-loadtest.sh) | k6 load + PM2 guard (bare metal) |
| [load.js](load.js) | k6 script — set `TARGET_URL` env var |

## Proof reports

- [SECURITY_AUDIT_AND_METRICS.md](../SECURITY_AUDIT_AND_METRICS.md)
- [HARDENED_PROOF_REPORT.md](../HARDENED_PROOF_REPORT.md)

## CI

GitHub Actions validates script syntax on every PR. See [.github/workflows/ci.yml](../.github/workflows/ci.yml).
