# Optional compose profiles (never Contabo default)

Heavy upstream stacks are **opt-in** via `elite-oneclick.sh enable <name>` or `--profile compose-*`.

| Feature | Upstream | Doc |
|---------|----------|-----|
| ig | Inspektor Gadget (already in physics pack) | [ig.md](ig.md) |
| netstacklat | Cloudflare ebpf_exporter examples | [netstacklat.md](netstacklat.md) |
| obi | OpenTelemetry eBPF Instrumentation | [obi.md](obi.md) |
| parca | Parca Agent continuous profiling | [parca.md](parca.md) |
| kepler | Kepler power metrics | [kepler.md](kepler.md) |
| sec | Tetragon observe-only | [sec.md](sec.md) |

CPUQuota must keep agent+pack under Contabo SLO. If after-working CPU check fails, leave feature disabled.
