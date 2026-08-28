# Benchmark Methodology

Engineering notes for Elite agent performance validation.

## CPU overhead

### Kubernetes mode

- Samples `kubectl top pod` every 5 seconds for `BENCH_DURATION` (default 60s).
- Computes average millicores, divides by 1000 for core fraction.
- **Pass:** ratio < `CPU_THRESHOLD` (default 0.01 = 1% of one core).

### systemd mode

- Reads `CPUUsageNSec` from cgroup via `systemctl show elite-agent`.
- Delta over window / duration = average cores in use.
- **Pass:** avg cores < 0.10 (10% hard ceiling; production target < 0.01).

## Memory

- Peak RSS from `MemoryCurrent` during 60s sustained `/metrics` scrape load.
- systemd `MemoryMax=160M` on bare-metal reference deploy.
- Stock binary BPF attach peak ~127 MB; 160M cap provides headroom.

## Load test (k6)

| Parameter | Default |
|-----------|---------|
| VUs | 30 |
| Duration | 60s |
| Target | `TARGET` env (localhost app port) |

**PM2-safe rule:** Never target PM2-managed ports without `pm2-guard.sh` running. Default stress scripts use closed ports or documented app ports with guard active.

## Kernel 6.8+ probe compatibility

| Probe | 6.8 status | Benchmark note |
|-------|------------|----------------|
| socketlatency | Pass | Primary latency signal |
| softirq | Pass | NET_RX slow path |
| packetloss | Pass | CO-RE tracepoint |
| tcpsummary | Pass | proc/sock_diag |
| kernellatency | Fail (`kfree_skb` kprobe) | Excluded from default bundle |
| connecttrace | Custom build only | Not in stock v1.0.0 image |

Exclude failing probes from config before benchmarking to avoid attach retry CPU noise.

## Event drop rate

Stock agent logs perf ring drops as:

```text
socketlatency perf event ring buffer full, drop: N
```

Under 50k TCP connect flood to closed port, journal showed **0% logged drops** on reference host (see HARDENED_PROOF_REPORT.md).

## Reproducibility

```bash
export BENCH_DURATION=60
export CPU_THRESHOLD=0.01
export ELITE_NAMESPACE=elite

./benchmarks/run-overhead.sh
./benchmarks/run-overhead.sh --mode systemd
```

Record: kernel version (`uname -r`), agent version, probe list from config, and raw script output.
