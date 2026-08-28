# Benchmark Plan

| ID | Config |
|----|--------|
| B0 | Physics closed-loop dry-run only |
| B1 | Static envelope, posture off |
| B2 | ECGF posture on |

Metrics: CPU cores, RSS, scrape p50/p99, deny latency, A1–A3 pass rate, PM2 restart sum.

Superiority: B2 ≥ B1 security (A1–A3) and ΔCPU ≤ 0.05 cores → else `NOT_PROVEN_SUPERIOR`.
