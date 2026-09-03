# Operational Provider Score (Physics-Speed Axes)

**Repository:** [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)
**Status:** Hard category score after Server LIVE proof (2026-08-28). See [CLAIM_CHARTER.md](CLAIM_CHARTER.md).

**Evidence roots:**

- Real closed-loop: `bash scripts/oneclick/live-real-closed-loop-proof.sh` → `REAL_CLOSED_LOOP_PASS`
- H11 LIVE: `scripts/oneclick/results/p1-live-*/` (`H11_PASS_LIVE`, `REAL_ONLY=1`)
- Bakeoff: `scripts/oneclick/results/category-bakeoff-*/` (`CATEGORY_BAKEOFF_PASS`)
- One-click suite: `bash scripts/oneclick/elite-run-safe.sh` (PM2 wrap, no mock inject)
- Category scorecard: [SERVER_CATEGORY_SCORECARD.md](SERVER_CATEGORY_SCORECARD.md)
- Gates helper: `scripts/oneclick/gates-checklist.sh`

| Dimension | Max | Score | Evidence |
|-----------|----:|------:|----------|
| Measured speed / overhead | 20 | 20 | Agent median CPU ≤0.05 cores (bakeoff 0.046667); prior SPEED_PASS |
| Physics signal coverage | 15 | 15 | Agent probes + LLC :9104 + Soft DCIC :9103 active |
| Predictive closed-loop | 15 | **15** | `H11_PASS_LIVE` — `elite_predict_*` scrape (artifact + Helm forecast enabled) |
| Classic pains P1-P10 | 20 | 18 | COMPETITOR_BASELINE_MATRIX + live closed-loop |
| Bare-metal / VPS readiness | 10 | 10 | oneclick/systemd server + metal `install.sh` execute path |
| Co-resident safety | 10 | 10 | PM2_GUARD_OK |
| Supply chain / Sonar / CI | 5 | 5 | Elite CI + claim-charter-grep + signed release (agent/updater/SHA256SUMS) |
| Docs honesty (DECLINE rows) | 5 | 5 | COMPETITOR_BASELINE_MATRIX + CLAIM_CHARTER + process-manager DECLINE |

```text
ELITE_OPS_SCORE
total=98/100
VERDICT=SERVER_PHYSICS_VPS_PASS
```

## Honesty

- Predictive **15/15** earned only with `H11_PASS_LIVE` (`elite_predict_*` present).
- Category bakeoff: `CATEGORY_BAKEOFF_PASS` (live predict + Soft DCIC + CPU ≤0.05).
- ECGF: `ECGF_BENCH_PASS` (separate axis).
- Still **DECLINE** Cilium/Tetragon/Falco/Pixie/Parca as overall products — this is **not** global eBPF #1.
- Still **DECLINE** process supervisors — Elite observes; it does not start/stop customer apps.
