# Elite Physics Metrics

Kernel-truth measurements — no application code changes.

| Metric | Probe | Layer | Meaning |
|--------|-------|-------|---------|
| `elite_socketlatency_read1ms` | socketlatency | L3 syscall | Socket read/write syscall delay |
| `elite_kernellatency_rxslow` | kernellatency | L2 kernel | Netfilter/route RX path delay |
| `elite_softirq_excuteslow` | softirq | L2 kernel | NET_RX/TX softirq scheduling delay |
| `elite_packetloss_total` | packetloss | L1 stack | Packets dropped in kernel |
| `elite_connecttrace_connect_total` | connecttrace | L4 TCP | Connect attempts (SYN_SENT transitions) |
| `elite_tcpsummary_tcpsynsentconn` | tcpsummary | L4 TCP | In-flight SYN_SENT sockets |
| `elite_tcpsummary_tcpestablishedconn` | tcpsummary | L4 TCP | Established connections |

## Enhanced eBPF (optional build)

`bpf/connect_trace.c` attaches to:
- `tracepoint/syscalls/sys_enter_connect`
- `tracepoint/syscalls/sys_exit_connect`

Build: `make generate-bpf-in-container`

## Overhead target

Agent CPU < 1% per node at 10k RPS (see `benchmarks/`).
