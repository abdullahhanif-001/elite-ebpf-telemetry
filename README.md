# Elite eBPF

**Zero-instrumentation kernel telemetry — one agent per node, under 1% CPU.**

Bakeoff scorecards and category claims: [docs/CLAIM_CHARTER.md](docs/CLAIM_CHARTER.md) · [docs/OPS_PROVIDER_SCORE.md](docs/OPS_PROVIDER_SCORE.md) · [docs/COMPETITIVE_PROOF.md](docs/COMPETITIVE_PROOF.md).

## Zero-Buffer Overload Controller (v1.0)

Kernel-native admission at XDP: token buckets, priority tiers, ringbuf λ, 50ms forecaster, federation push. Policy map v3 (80B) in [`bpf/policy_map.h`](bpf/policy_map.h).

```bash
bash scripts/oneclick/elite-zero-buffer-complete.sh
```

Docs: [docs/ADR-007-xdp-v3-admission.md](docs/ADR-007-xdp-v3-admission.md) · [docs/ADR-006-predictive-xdp-shedding.md](docs/ADR-006-predictive-xdp-shedding.md) · [docs/MICROSOFT_REVIEW_PACK.md](docs/MICROSOFT_REVIEW_PACK.md) · [docs/RELEASE_v1.0_ZERO_BUFFER.md](docs/RELEASE_v1.0_ZERO_BUFFER.md)

Replace per-pod Istio sidecars and log shippers with a single eBPF DaemonSet (or systemd service) that exports physics-layer metrics: socket latency, softirq delay, packet loss, and TCP summary.

**Author & creator:** Abdullah Hanif  
**Brand:** Elite eBPF — personal open-source project  
**Repository:** [github.com/abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)

## Contributors

**Abdullah Hanif** — sole creator, author, and maintainer. See [AUTHORS.md](AUTHORS.md).

---

## sched_ext RT Guard — [scx#1202](https://github.com/sched-ext/scx/issues/1202) verified fix

**Problem:** RT tasks monopolize CPU → EXT scheduler tasks stall → kernel watchdog ejects the BPF scheduler ([sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)).

**Status:** **Development in progress** — verified on server sched_ext kernel (`REAL_ONLY=1`). Upstream PR withdrawn temporarily while we finish dev (scx_loader, full gate matrix). Issue [#1202](https://github.com/sched-ext/scx/issues/1202) open.

**Solution (verified on real VPS, `REAL_ONLY=1`, no mocks):**

| Layer | Fix | Artifact |
|-------|-----|----------|
| L1 | ext_server DL server | Andrea Righi `scx-dl-server` branch |
| L2 | RT-aware watchdog | [`contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`](contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch) |
| L3 | BPF preemption interceptor | [`contrib/sched-ext/bpf/scx_rt_guard.bpf.h`](contrib/sched-ext/bpf/scx_rt_guard.bpf.h) + [`rt_guard_stress`](contrib/sched-ext/selftests/) selftest |

**Proof (production server, kernel `6.19.0-rc7` + ftrace + sched_ext):**

| Gate | Verdict |
|------|---------|
| SCX1202 gate matrix H1–H12 (#1202 matrix) | **12/12 PASS** — `SCX1202_MATRIX_PASS=YES` |
| #1202 repro with bpfland | **`STALL_DETECTED=NO`** |
| Global eBPF D1–D6 | **`GLOBAL_EBPF_PASS`** (`fail=0`) |
| RT Guard flood P1–P5 | **`RT_GUARD_FLOOD_PASS`** |

Full published report: **[docs/GLOBAL_EBPF_VERIFICATION_REPORT.md](docs/GLOBAL_EBPF_VERIFICATION_REPORT.md)**  
Committed evidence (auditor verify): **[docs/evidence/scx-1202/README.md](docs/evidence/scx-1202/README.md)** — run `bash scripts/verify-scx-1202-evidence.sh`  
Google/interview brief: **[docs/evidence/scx-1202/GOOGLE_VERIFICATION_BRIEF.md](docs/evidence/scx-1202/GOOGLE_VERIFICATION_BRIEF.md)**  
Upstream PR tracker: **[docs/evidence/scx-1202/UPSTREAM_PR_TRACKER.md](docs/evidence/scx-1202/UPSTREAM_PR_TRACKER.md)**  
sched_ext evidence pack: **[contrib/sched-ext/EVIDENCE_REPORT.md](contrib/sched-ext/EVIDENCE_REPORT.md)**  
Upstream PR body (ready): **[contrib/sched-ext/GITHUB_PR_BODY.md](contrib/sched-ext/GITHUB_PR_BODY.md)** — `Fixes sched-ext/scx#1202`

Reproduce on a sched_ext host:

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash benchmarks/ebpf-gates/scx1202-matrix-verify.sh
bash benchmarks/ebpf-gates/global-ebpf-aggregate.sh
```

Upstream submission: [`scripts/server/submit-rt-guard-upstream.sh`](scripts/server/submit-rt-guard-upstream.sh) · tracking: [contrib/sched-ext/UPSTREAM_TRACKING.md](contrib/sched-ext/UPSTREAM_TRACKING.md)

---

## What’s new

### Elite Physics Pack (OSS compose under systemd)

Production-shaped **compose**, not a demo script: pinned GitHub release digests (`versions.env`), Cloudflare `ebpf_exporter` + optional Inspektor Gadget + `bpfcc-tools`, dedicated systemd units with CPUQuota, localhost-only Prometheus scrape glue, Grafana dashboard JSON, and a Server proof harness that samples process CPU without touching co-resident PM2 apps.

```bash
sudo bash scripts/oneclick/elite-physics-pack.sh install
bash scripts/oneclick/physics-pack-proof.sh
```

Design constraint (ADR-003): **no new kernel BPF inventions** — Elite brands and operates upstream CO-RE artifacts with required attribution. Pins + license notes: [scripts/oneclick/ATTRIBUTION.md](scripts/oneclick/ATTRIBUTION.md), [docs/ADR-003-oneclick-oss-compose.md](docs/ADR-003-oneclick-oss-compose.md).

### Deterministic predictive layer (`pkg/forecaster`)

Userspace **control-plane** fault projection over physics latency series — pure math, **no ML model**, **no new eBPF**. The agent scrapes loopback Prometheus text (`:9435` / `:9102` / optional `:9104` LLC), fuses network + LLC + PSI, then runs a fixed-cost pipeline designed for always-on VPS duty:

| Stage | Implementation detail |
|-------|------------------------|
| Scrape parse | Reusable 256 KiB body buffers; prefix match on `[]byte` (no string concat); fixed counter slots (no per-tick maps) |
| Fuse | Weighted network / LLC / PSI → scalar; causal argmax → `elite_predict_fault_cause` |
| Smooth | EWMA α=0.3 over an 8-sample ring |
| Kinematics | Velocity + acceleration from EWMA deltas; 5s projection `s + v·t + ½a·t²` when accelerating |
| Fault trip | Projected ≥ hardDrop **and** EWMA ≥ 30% of hardDrop (rejects flap false positives) |
| Publish | Double-buffered `Snapshot`; decision bus `/var/lib/elite/predict-decision.json` for Soft DCIC |
| Actuate | `dry-run` / `semi` (shed events only for `network|mixed`); Soft cgroup + optional resctrl CAT |

One-click: `sudo bash scripts/oneclick/elite-oneclick.sh install --profile closed-loop` then `test --suite after-working`. ADR-004.

Server A-grade gate (`forecaster-agrade.sh`): benchmem **0 B/op / 0 allocs/op** on parse/observe hot paths, PM2 process-set invariant before/after — only claim switch-readiness when `VERDICT=SWITCH_READY` ([scripts/oneclick/SCORECARD_SWITCH.md](scripts/oneclick/SCORECARD_SWITCH.md)). `SOFT_ONLY` is success when hardware lacks resctrl.

```yaml
forecast:
  enabled: true
  interval: 1s
  horizon: 5s
  mode: dry-run   # or semi
  hardDropSeconds: 0.1
  llcURL: "http://127.0.0.1:9104/metrics"
  readPSI: true
```

Series: `elite_predict_*` including `elite_predict_fault_cause{cause=...}`. Docs: [docs/predictive-forecaster.md](docs/predictive-forecaster.md), [docs/ADR-004-closed-loop-predict-actuate.md](docs/ADR-004-closed-loop-predict-actuate.md).

---

## One-click install

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
chmod +x install.sh
sudo ./install.sh --mode metal --profile full
```

Remote (metal):

```bash
curl -fsSL https://raw.githubusercontent.com/abdullahhanif-001/elite-ebpf-telemetry/main/install.sh \
  | sudo bash -s -- --mode metal --profile full
```

| Environment | What happens |
|-------------|--------------|
| Kubernetes | `kubectl apply -f deploy/elite-bundle.yaml` |
| Linux VPS | Downloads signed release (or local/build), installs systemd `elite-agent` + optional `elite-updater.timer`, runs oneclick profile |

Force a mode:

```bash
./install.sh --mode k8s
./install.sh --mode metal --profile physics
./install.sh --dry-run
```

Auto-update: `elite-updater` + `elite-updater.timer` (SHA256 / optional cosign). Rollback: [deploy/server/ROLLBACK.md](deploy/server/ROLLBACK.md). Gates: `bash scripts/oneclick/gates-checklist.sh`.

---

## Architecture

```text
Kernel tracepoints → eBPF CO-RE → elite-agent (Go) → Prometheus (:9102) + OTLP
                         ↘ scrape :9435 / :9104 / PSI → fuse+EWMA → elite_predict_*
                         ↘ Soft DCIC (:9103) ← decision bus ← predict fault
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

See [deploy/server/](deploy/server/) — systemd unit, PM2 guard, Prometheus/Grafana on localhost only.

**Server repro (VPS only — no local go test on Windows):**

```bash
# From PC: sync src only (never overwrite /opt/elite/scripts)
scp -r update-ebpf/* production-server:/opt/elite/src/

# On VPS: PM2-safe real proof suite (no mock inject, no pm2 restart)
ssh production-server 'bash /opt/elite/src/scripts/oneclick/elite-run-safe.sh'

# Pass verdicts: REAL_CLOSED_LOOP_PASS, H11_PASS_LIVE, SPEED_PASS,
# CATEGORY_BAKEOFF_PASS, PM2_GUARD_OK, ADVERSARIAL AUDIT FAILURES=0
# Retire legacy ebpf_exporter only after proofs:
ssh production-server 'systemctl stop elite-ebpf-exporter'
```

---

## Benchmarks

```bash
./benchmarks/run-overhead.sh              # Kubernetes
./benchmarks/run-overhead.sh --mode systemd
bash scripts/oneclick/forecaster-agrade.sh  # server: 0-alloc + SWITCH_READY scorecard
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

Full market matrix (Retina, Tetragon, Pixie, DeepFlow, Hubble, Istio, Beyla, BCC, …): **[docs/COMPETITOR_BASELINE_MATRIX.md](docs/COMPETITOR_BASELINE_MATRIX.md)**. Executive: [docs/COMPETITIVE_PROOF.md](docs/COMPETITIVE_PROOF.md).

| | Istio sidecar | OBI | Retina | Pixie | **Elite** |
|---|--------------|-----|--------|-------|-----------|
| Per-pod overhead | ~500m CPU | 0 | 0 | heavy agent class | **0** |
| Socket physics metrics | No | Partial | Partial | Partial | **Yes** |
| Predictive fault gauges | No | No | No | No | **`elite_predict_*`** |
| Soft density actuate (VPS) | No | No | No | No | **Soft DCIC** |
| Bare VPS one-click pack | No | No | Helm/K8s | K8s | **Physics Pack** |
| SecOps attack-block | No | No | No | No | **DECLINE** (Tetragon's axis) |

Speed/overhead proofs: `bash scripts/oneclick/competitive-speed-proof.sh` · `competitive-overhead-proof.sh`.

---

## License

- Userspace: Apache-2.0 ([LICENSE-ELITE.md](LICENSE-ELITE.md))
- BPF `/bpf`: GPL-2.0

---

## Docs

- [Global eBPF verification report (#1202)](docs/GLOBAL_EBPF_VERIFICATION_REPORT.md)
- [sched_ext RT Guard upstream pack](contrib/sched-ext/README.md)
- [Track C ECGF research](docs/research/MASTER_REPORT.md)
- [ADR-005 Track C](docs/ADR-005-track-c-ecgf.md)
- [World eBPF comparison](docs/COMPETITOR_BASELINE_MATRIX.md)
- [Competitive proof](docs/COMPETITIVE_PROOF.md)
- [Operational provider score](docs/OPS_PROVIDER_SCORE.md)
- [Physics metrics](docs/physics-metrics.md)
- [Sidecar removal](docs/sidecar-removal.md)
- [ADR-001: Elite architecture](docs/ADR-001-fork-base.md)
- [ADR-003: One-click OSS compose](docs/ADR-003-oneclick-oss-compose.md)
- [Predictive forecaster](docs/predictive-forecaster.md)
- [Physics Pack README](scripts/oneclick/README.md)
- [AUTHORS.md](AUTHORS.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
