# World eBPF Comparison — Physics + Speed Provider Matrix

**Project:** Elite eBPF Telemetry  
**Maintainer / Org:** Abdullah Hanif / [`abdullahhanif-001`](https://github.com/abdullahhanif-001)  
**Repository:** [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)  
**Core strength (Khasiyat):** Fastest practical **physics-layer** eBPF path + **0-alloc kinematic predict** + Soft density actuate on **one VPS**  
**World claim (scored):** Best **physics-speed production provider** on the public rubric in [WORLD_BEST_PROVIDER_SCORE.md](WORLD_BEST_PROVIDER_SCORE.md) — evidence-backed, not pitched.

**Fork honesty:** Go module path remains `github.com/alibaba/kubeskoop` (KubeSkoop lineage). Elite brands, hardens, predicts, and actuates on top. See [scripts/oneclick/ATTRIBUTION.md](../scripts/oneclick/ATTRIBUTION.md).

**We do not claim:** inventing eBPF, beating Tetragon at attack-block, replacing DeepFlow APM, or being the “only” eBPF stack.

---

## Classic eBPF pains Elite solves

| # | Pain | Market failure | Elite fix | Proof artifact |
|---|------|----------------|-----------|----------------|
| P1 | Sidecar tax (~500mCPU/pod Istio) | Density collapse | One agent/node | [COMPETITIVE_SPEED.md](../scripts/oneclick/COMPETITIVE_SPEED.md) S4 + Contabo CPU |
| P2 | K8s-only tooling | No bare VPS path | systemd Contabo first-class | Physics Pack / one-click (no CNI) |
| P3 | Heavy agents (Pixie-class memory) | Cannot co-reside | `MemoryMax=160M`, ~72MB RSS class | [COMPETITIVE_OVERHEAD.md](../scripts/oneclick/COMPETITIVE_OVERHEAD.md) |
| P4 | Metrics without prediction | Alert after outage | EWMA + kinematics | `elite_predict_*` + 0-alloc benches |
| P5 | Observe-only | Dashboards do not shed noise | Soft DCIC + decision bus | live predict proof H11 |
| P6 | Unsafe shared-VPS deploys | Neighbor PM2 restarts | `pm2-guard.sh` | `PM2_GUARD_OK` |
| P7 | Invent-or-die BPF | Scratch programs | OSS compose pins (ADR-003) | `versions.env` + ATTRIBUTION + physics-pack-proof |
| P8 | Flappy alerts | Raw thresholds | EWMA flap floor | unit goldens + H11 |
| P9 | No causal blame | “latency high” only | fuse network/LLC/PSI | `elite_predict_fault_cause` |
| P10 | Open debug surface | pprof/status exposed | hardened 404 mux | [AUDIT_SCORECARD.md](../AUDIT_SCORECARD.md) |

---

## Market matrix

Scores are **0–5** on Elite’s axes (speed = overhead/ops cost; physics = L3/L4 kernel signal depth). `DECLINE` = different product category.

### Physics / kernel metrics

| Project | Org | Strength | Speed | Physics | Verdict | Notes |
|---------|-----|----------|------:|--------:|---------|-------|
| Elite agent + Physics Pack | Abdullah Hanif | Always-on physics + predict | 5 | 5 | **WIN (baseline)** | Contabo proven |
| Cloudflare ebpf_exporter | Cloudflare | Example-driven kernel metrics | 4 | 4 | PEER (compose) | Elite operates it in pack; we add predict/actuate |
| BCC / bpfcc-tools | IO Visor | Ad-hoc tracing | 2 | 4 | WIN (ops) | Scripts ≠ always-on Prometheus |
| Inspektor Gadget | Kinvolk/IG | Gadgets / optional metrics | 3 | 3 | PEER (optional) | Compose-only on Contabo |
| Kepler | CNCF | Energy | 3 | 1 | DECLINE | Energy axis not our product |
| Parca | Polar Signals | Continuous profiling | 2 | 1 | DECLINE | Profiles optional compose |

### Network / K8s observability

| Project | Org | Strength | Speed | Physics | Verdict | Notes |
|---------|-----|----------|------:|--------:|---------|-------|
| Microsoft Retina | Microsoft | Cluster drops/latency | 3 | 4 | PEER K8s / **WIN VPS** | Retina needs K8s; Elite systemd wins bare metal |
| Cilium Hubble | Isovalent/Cisco | CNI flow visibility | 3 | 4 | WIN (no-CNI VPS) | Requires Cilium dataplane |
| DeepFlow | Yunshan | Zero-code distributed tracing | 2 | 2 | DECLINE APM / WIN physics-speed | App tracing ≠ socket/softirq physics |

### Security / runtime

| Project | Org | Strength | Speed | Physics | Verdict | Notes |
|---------|-----|----------|------:|--------:|---------|-------|
| Cilium Tetragon | Isovalent/Cisco | Realtime enforcement | 3 | 2 | **DECLINE** | SecOps block — ADR-004 rejects default-on |
| Process supervisors (pm2/systemd/supervisord) | — | App lifecycle start/stop | n/a | 0 | **DECLINE** | Elite observes workloads via eBPF compose; it is **not** a process manager and does not start/stop customer apps |

### Debug / heavy agents

| Project | Org | Strength | Speed | Physics | Verdict | Notes |
|---------|-----|----------|------:|--------:|---------|-------|
| Pixie | CNCF / New Relic | In-cluster debug + flame graphs | 1 | 2 | **WIN mem/CPU/VPS** / DECLINE PxL | Heavy footprint class |

### Sidecar / auto-instr

| Project | Org | Strength | Speed | Physics | Verdict | Notes |
|---------|-----|----------|------:|--------:|---------|-------|
| Istio sidecar | Istio | L7 mesh | 1 | 1 | **WIN speed** | Sidecar tax vs one agent |
| Grafana Beyla / OBI | Grafana | Zero-code app eBPF metrics | 3 | 2 | PEER idea / WIN physics default | Contabo default stays physics-light |

### Elite-only differentiator

| Axis | Elite | Market default | Verdict |
|------|-------|----------------|---------|
| VPS closed-loop Soft density | MOCK_ inject → `elite_predict_*` → Soft `cpu.max` | None of the above as Contabo systemd default | **WIN** |

---

## How to re-prove

```bash
sudo bash scripts/oneclick/elite-oneclick.sh install --profile closed-loop
bash scripts/oneclick/competitive-speed-proof.sh
bash scripts/oneclick/competitive-overhead-proof.sh
bash scripts/oneclick/competitive-live-predict-proof.sh
bash scripts/oneclick/elite-oneclick.sh test --suite heavy
```

Executive summary: [COMPETITIVE_PROOF.md](COMPETITIVE_PROOF.md). Rubric: [WORLD_BEST_PROVIDER_SCORE.md](WORLD_BEST_PROVIDER_SCORE.md).
