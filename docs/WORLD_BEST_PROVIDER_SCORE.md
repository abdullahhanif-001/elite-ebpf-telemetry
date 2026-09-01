# World Best Provider Score (Physics-Speed Axes)

> **Deprecated:** Use [TEST_BENCHMARK_REGISTRY.md](TEST_BENCHMARK_REGISTRY.md) and [EBPF_FEATURE_INVENTORY.md](EBPF_FEATURE_INVENTORY.md) for current gate and feature documentation. This file retains historical Phase B verdict data.

**Repository:** [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)
**Status:** Hard category score after Contabo LIVE proof (2026-08-28). See [CLAIM_CHARTER.md](CLAIM_CHARTER.md).

**Evidence roots:**

- Real closed-loop: `bash scripts/oneclick/live-real-closed-loop-proof.sh` → `REAL_CLOSED_LOOP_PASS`
- H11 LIVE: `scripts/oneclick/results/p1-live-*/` (`H11_PASS_LIVE`, `REAL_ONLY=1`)
- Bakeoff: `scripts/oneclick/results/category-bakeoff-*/` (`CATEGORY_BAKEOFF_PASS`)
- One-click suite: `bash scripts/oneclick/elite-run-safe.sh` (PM2 wrap, no mock inject)
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
| Supply chain / Sonar / CI | 5 | 5 | Elite CI + claim-charter-grep + signed release (agent/updater/SHA256SUMS) |
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
