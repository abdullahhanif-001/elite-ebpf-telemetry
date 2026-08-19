# Elite eBPF

**Zero-instrumentation kernel telemetry — one agent per node, under 1% CPU.**

Replace per-pod Istio sidecars and log shippers with a single eBPF DaemonSet (or systemd service) that exports physics-layer metrics: socket latency, softirq delay, packet loss, and TCP summary.

**Author:** abdullah i  
**Repository:** [github.com/abdullahanifpro111-spec/elite-ebpf](https://github.com/abdullahanifpro111-spec/elite-ebpf)  
**Upstream fork:** [KubeSkoop](https://github.com/alibaba/kubeskoop) (Apache-2.0 / GPL BPF)

---

## One-click install

```bash
git clone https://github.com/abdullahanifpro111-spec/elite-ebpf.git
cd elite-ebpf
chmod +x install.sh
./install.sh
```

| Environment | What happens |
|-------------|--------------|
| Kubernetes | `kubectl apply -f deploy/elite-bundle.yaml` |
| Linux VPS | Prints systemd deploy steps from `deploy/contabo/` |

Force a mode:

```bash
./install.sh --mode k8s
./install.sh --mode metal
./install.sh --dry-run
```

---

## Architecture

```text
Kernel tracepoints → eBPF CO-RE → elite-agent (Go) → Prometheus (:9102) + OTLP
```

Default metric prefix: `elite_*` (custom build). Stock KubeSkoop image uses `kubeskoop_*` until rebuilt from this repo.

---

## Metrics

| Prefix | Source |
|--------|--------|
| `elite_socketlatency_*` | Socket syscall latency |
| `elite_softirq_*` | NET_RX softirq delay |
| `elite_packetloss_*` | Kernel drop tracepoints |
| `elite_tcpsummary_*` | TCP connection stats |
| `elite_connecttrace_*` | TCP connect (custom build) |

Details: [docs/physics-metrics.md](docs/physics-metrics.md)

---

## Production options

**Helm:**

```bash
helm install elite ./deploy/helm/elite \
  --namespace elite --create-namespace
```

**Bare metal (PM2-safe VPS):**

See [deploy/contabo/](deploy/contabo/) — systemd unit, PM2 guard, Prometheus/Grafana on localhost only.

---

## Benchmarks

```bash
./benchmarks/run-overhead.sh              # Kubernetes
./benchmarks/run-overhead.sh --mode systemd
```

SLO: agent CPU < 1% core fraction. Methodology: [benchmarks/BENCHMARKS.md](benchmarks/BENCHMARKS.md)

---

## Build from source

```bash
make generate-bpf-in-container
make build-exporter
```

Requires Linux, clang, Go 1.22+.

---

## Security

- Loopback-only metrics bind by default (`127.0.0.1:9102`)
- Hardened systemd: `NoNewPrivileges`, memory cap, minimal caps
- Audit reports: [SECURITY_AUDIT_AND_METRICS.md](SECURITY_AUDIT_AND_METRICS.md), [HARDENED_PROOF_REPORT.md](HARDENED_PROOF_REPORT.md)

---

## Comparison

| | Istio sidecar | OBI | Retina | **Elite** |
|---|--------------|-----|--------|-----------|
| Per-pod overhead | ~500m CPU | 0 | 0 | **0** |
| Socket physics metrics | No | Partial | Partial | **Yes** |
| One-click deploy | No | Helm | Helm | **`./install.sh`** |
| OTel native | Via mesh | Yes | Prom only | **Yes** |

---

## License

- Userspace: Apache-2.0 ([LICENSE-ELITE.md](LICENSE-ELITE.md))
- BPF `/bpf`: GPL-2.0

---

## Docs

- [Physics metrics](docs/physics-metrics.md)
- [Sidecar removal](docs/sidecar-removal.md)
- [ADR-001: Fork base](docs/ADR-001-fork-base.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
