# Elite eBPF

**Zero-instrumentation kernel telemetry — one agent per node, under 1% CPU.**

Replace per-pod Istio sidecars and log shippers with a single eBPF DaemonSet (or systemd service) that exports physics-layer metrics: socket latency, softirq delay, packet loss, and TCP summary.

**Author & creator:** Abdullah Hanif  
**Brand:** Elite eBPF — personal open-source project  
**Repository:** [github.com/abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)

## Contributors

**Abdullah Hanif** — sole creator, author, and maintainer. See [AUTHORS.md](AUTHORS.md).

---

## What’s new

### Elite Physics Pack (OSS compose under systemd)

Production-shaped **compose**, not a demo script: pinned GitHub release digests (`versions.env`), Cloudflare `ebpf_exporter` + optional Inspektor Gadget + `bpfcc-tools`, dedicated systemd units with CPUQuota, localhost-only Prometheus scrape glue, Grafana dashboard JSON, and a Contabo proof harness that samples process CPU without touching co-resident PM2 apps.

```bash
sudo bash scripts/oneclick/elite-physics-pack.sh install
bash scripts/oneclick/physics-pack-proof.sh
```

Design constraint (ADR-003): **no new kernel BPF inventions** — Elite brands and operates upstream CO-RE artifacts with required attribution. Pins + license notes: [scripts/oneclick/ATTRIBUTION.md](scripts/oneclick/ATTRIBUTION.md), [docs/ADR-003-oneclick-oss-compose.md](docs/ADR-003-oneclick-oss-compose.md).

### Deterministic predictive layer (`pkg/forecaster`)

Userspace **control-plane** fault projection over physics latency series — pure math, **no ML model**, **no new eBPF**. The agent scrapes loopback Prometheus text (`:9435` / `:9102`), then runs a fixed-cost pipeline designed for always-on VPS duty:

| Stage | Implementation detail |
|-------|------------------------|
| Scrape parse | Reusable 256 KiB body buffers; prefix match on `[]byte` (no string concat); fixed counter slots (no per-tick maps) |
| Smooth | EWMA α=0.3 over an 8-sample ring |
| Kinematics | Velocity + acceleration from EWMA deltas; 5s projection `s + v·t + ½a·t²` when accelerating |
| Fault trip | Projected ≥ hardDrop **and** EWMA ≥ 30% of hardDrop (rejects flap false positives) |
| Publish | Double-buffered `Snapshot` (no per-tick `atomic.Pointer` alloc); gauges `elite_predict_*` |
| Actuate | `dry-run` (metrics/logs) or `semi` (temporary event-probe shed via existing Reload, metrics stay up) |

Contabo A-grade gate (`forecaster-agrade.sh`): benchmem **0 B/op / 0 allocs/op** on parse/observe hot paths, PM2 process-set invariant before/after, honest Retina comparison — only claim switch-readiness when `VERDICT=SWITCH_READY` ([scripts/oneclick/SCORECARD_SWITCH.md](scripts/oneclick/SCORECARD_SWITCH.md)).

```yaml
forecast:
  enabled: true
  interval: 1s
  horizon: 5s
  mode: dry-run   # or semi
  hardDropSeconds: 0.1
```

Series: `elite_predict_latency_ewma_seconds`, `elite_predict_velocity`, `elite_predict_acceleration`, `elite_predict_projected_5s_seconds`, `elite_predict_fault`, `elite_predict_faults_total`. Full design notes: [docs/predictive-forecaster.md](docs/predictive-forecaster.md).

---

## One-click install

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
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
                         ↘ optional: scrape :9435 → EWMA forecaster → elite_predict_*
```

Default metric prefix: **`elite_*`** — configured via `metrics.metricNamespace` in YAML or `ELITE_METRICS_NAMESPACE` env. Build **`bin/elite-agent`** from this repo.

### Why Elite (Abdullah Hanif)

| Layer | Elite eBPF |
|-------|------------|
| Metric namespace | **`elite_*`** via `SetMetricsNamespace()` + config |
| Probe set | **Physics-only** slim set (<1% CPU) |
| HTTP surface | **Hardened mux**, pprof 404, localhost bind |
| Deploy | **`elite-bundle.yaml`** + `install.sh` |
| OTel | **OTLP bridge** (`pkg/export/`) |
| Predict | **EWMA forecaster** (`pkg/forecaster/`) |
| Binary | **`elite-agent`** |
| Container | **`ghcr.io/abdullahhanif-001/elite-ebpf-telemetry/agent`** |

---

## Metrics

| Prefix | Source |
|--------|--------|
| `elite_socketlatency_*` | Socket syscall latency |
| `elite_softirq_*` | NET_RX softirq delay |
| `elite_packetloss_*` | Kernel drop tracepoints |
| `elite_tcpsummary_*` | TCP connection stats |
| `elite_connecttrace_*` | TCP connect (custom build) |
| `elite_predict_*` | Userspace EWMA fault forecast |

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
bash scripts/oneclick/forecaster-agrade.sh  # Contabo: 0-alloc + SWITCH_READY scorecard
```

SLO: agent CPU < 1% core fraction. Methodology: [benchmarks/BENCHMARKS.md](benchmarks/BENCHMARKS.md)

---

## Build from source

```bash
make generate-bpf-in-container
make build-elite-agent    # → bin/elite-agent
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
| Predictive fault gauges | No | No | No | **`elite_predict_*`** |
| Bare VPS one-click pack | No | No | Helm/K8s | **Physics Pack** |
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
- [ADR-001: Elite architecture](docs/ADR-001-fork-base.md)
- [ADR-003: One-click OSS compose](docs/ADR-003-oneclick-oss-compose.md)
- [Predictive forecaster](docs/predictive-forecaster.md)
- [Physics Pack README](scripts/oneclick/README.md)
- [AUTHORS.md](AUTHORS.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
