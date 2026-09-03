# ECGF Track C — Master Research Report

## Executive Summary

Elite Track C delivers **ECGF-lite**: physics-triggered security posture over **existing** Soft DCIC + consequence envelopes (systemd/Landlock/seccomp compose). Novel BPF, Tetragon clones, and Sandlock clones are **REJECTED**. Server B2 vs B1 measured: **`ECGF_BENCH_PASS`**.

## Current eBPF State / Competitive Landscape

See [COMPETITOR_BASELINE_MATRIX.md](../COMPETITOR_BASELINE_MATRIX.md), [PRIOR_ART_MATRIX.md](PRIOR_ART_MATRIX.md), [SOURCES.md](SOURCES.md).

## Unsolved Problem Map

See [PROBLEM_INDEX.md](PROBLEM_INDEX.md) and `problems/U01.md`–`U12.md`.

## Novel Research Gap

See [NOVEL_GAP.md](NOVEL_GAP.md) — **SURVIVE** ECGF-lite only.

## Proposed Architecture

See [ARCHITECTURE_ECGF.md](ARCHITECTURE_ECGF.md), [ADR-005](../ADR-005-track-c-ecgf.md).

## Mathematical / Threat / Stability / Benchmark

[MATH_MODEL.md](MATH_MODEL.md) · [THREAT_MODEL.md](THREAT_MODEL.md) · [STABILITY_MODEL.md](STABILITY_MODEL.md) · [BENCHMARK_PLAN.md](BENCHMARK_PLAN.md)

## Problems Solved / Partial / Unsolved

| Class | Items |
|-------|-------|
| Rejected inventions | U08, U09, novel BPF, Tetragon/Falco/Sandlock/AgentCgroup clones |
| Surviving build | U11 coupling (hypothesis), U12 honesty |
| Open research | U01 verifier, etc. — not Elite scope |

## Feature Inventory

- `pkg/ecgf` + `cmd/elite-ecgf` (:9105)
- `ecgf-envelope.sh`, `ecgf-redteam.sh`, `ecgf-bench.sh`
- Profile `ecgf` / `elite-ecgf-pack.sh`

## Server Evidence (2026-08-24)

| Gate | Result |
|------|--------|
| Red-team A1–A3 | **PASS** (`results/ecgf-redteam-latest.txt`) |
| Red-team verdict | `ECGF_REDTEAM_PASS` |
| Bench B0/B1/B2 | **Measured** — ΔCPU ≤ 0.05; A1–A3 OK |
| B2 vs B1 superiority | **`ECGF_BENCH_PASS`** — see `scripts/oneclick/ECGF_BENCH.md` |
| Live `elite_predict_*` | **`H11_PASS_LIVE`** (`results/p1-live-20260824-111335/`) |
| Category bakeoff | **`CATEGORY_BAKEOFF_PASS`** |
| PM2 | `PM2_GUARD_OK` |

MVP posture+envelope: **ECGF_MVP_PASS**. Superiority: **ECGF_BENCH_PASS**.

## Final Verdict

```text
ELITE_ECGF_TRACK_C
novelty=SURVIVE_NARROW_INTEGRATION
bpf_invention=REJECTED
mvp=ECGF_MVP_PASS
VERDICT=ECGF_BENCH_PASS
```

Honesty: MOCK decision bus ≠ live predict PASS (H11 LIVE required). Server category is Server physics-speed VPS bakeoff only — see [CLAIM_CHARTER.md](../CLAIM_CHARTER.md).
