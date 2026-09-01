# World Best Provider Score (Physics-Speed Axes)

> **Deprecated:** Use [docs/TEST_BENCHMARK_REGISTRY.md](../../docs/TEST_BENCHMARK_REGISTRY.md) and [docs/EBPF_FEATURE_INVENTORY.md](../../docs/EBPF_FEATURE_INVENTORY.md) for current documentation. This file retains historical Phase B verdict data.

**Repository:** [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)
**Status:** Hard category score after Contabo LIVE proof (2026-08-28 Phase B). See [CLAIM_CHARTER.md](CLAIM_CHARTER.md).

**Phase B evidence:**

- Staff pack: [scripts/oneclick/PHASE_B_VPS_PROOF_REPORT.md](../scripts/oneclick/PHASE_B_VPS_PROOF_REPORT.md)
- eBPF X-Ray: [scripts/oneclick/EBPF_XRAY_REPORT.md](../scripts/oneclick/EBPF_XRAY_REPORT.md) (`REAL_EBPF_XRAY_PASS`)
- W4 gate: [scripts/oneclick/W4_XDP_GATE_REPORT.md](../scripts/oneclick/W4_XDP_GATE_REPORT.md) (p99 from `results/w4-xdp-inject-latest.txt` after VPS run)
- Gates 8/8: [scripts/oneclick/GATES_8_8_REPORT.md](../scripts/oneclick/GATES_8_8_REPORT.md)

**Evidence roots:**

- H11 LIVE: `scripts/oneclick/results/p1-live-20260824-111335/` (`H11_PASS_LIVE`)
- Bakeoff: `scripts/oneclick/results/category-bakeoff-20260824-111658/`
- Category scorecard: [CATEGORY_NUMBER_ONE_SCORECARD.md](CATEGORY_NUMBER_ONE_SCORECARD.md)
- Gates helper: `scripts/oneclick/gates-checklist.sh`

| Dimension | Max | Score | Evidence |
|-----------|----:|------:|----------|
| Measured speed / overhead | 20 | 20 | Agent median CPU ≤0.05 cores (bakeoff 0.046667); prior SPEED_PASS |
| Physics signal coverage | 15 | 15 | Agent probes + LLC :9104 + Soft DCIC :9103 active |
| Predictive closed-loop | 15 | **15** | `H11_PASS_LIVE` — `elite_predict_*` scrape (artifact + Helm forecast enabled) |
| Classic pains P1-P10 | 20 | 18 | WORLD_EBPF_COMPARISON + live closed-loop |
| Bare-metal / VPS readiness | 10 | 10 | oneclick/systemd Contabo + metal `install.sh` execute path |
| Co-resident safety | 10 | 10 | PM2_GUARD_OK |
| Supply chain / Sonar / CI | 5 | 5 | SonarCloud A-grade + Elite CI + check green on `main` |
| Docs honesty (DECLINE rows) | 5 | 5 | WORLD_EBPF_COMPARISON + CLAIM_CHARTER + process-manager DECLINE |

```text
ELITE_WORLD_BEST
total=98/100
VERDICT=WORLD_BEST_PHYSICS_SPEED_VPS
```

## Honesty

- Predictive **15/15** earned only with `H11_PASS_LIVE` (`elite_predict_*` present).
- Category bakeoff: `CATEGORY_BAKEOFF_PASS` (live predict + Soft DCIC + CPU ≤0.05).
- ECGF: `ECGF_PROVEN_SUPERIOR` (separate axis).
- Still **DECLINE** Cilium/Tetragon/Falco/Pixie/Parca as overall products — this is **not** global eBPF #1.
- Still **DECLINE** process supervisors — Elite observes; it does not start/stop customer apps.
