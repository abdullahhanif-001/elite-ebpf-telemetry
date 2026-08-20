# ADR-001: Elite eBPF Architecture Base

## Status

Accepted

## Context

Istio sidecars and per-pod logging agents waste ~20% cluster CPU/RAM. Building every eBPF probe from zero is slow and unproven for production.

## Decision

**Elite eBPF** (by abdullah i) uses a production-grade eBPF agent architecture:

- Metric namespace **`elite_*`** (config-driven)
- Slim physics probe set (socket latency, softirq, packet loss, TCP summary, connect trace)
- OpenTelemetry OTLP export bridge
- One-click `elite-bundle.yaml` and `install.sh`
- Security-hardened agent (localhost bind, no public pprof)

## Consequences

- Userspace Go: Apache-2.0
- BPF programs in `/bpf`: GPL-2.0 (kernel compatibility)
- Personal brand and maintenance by abdullah i
