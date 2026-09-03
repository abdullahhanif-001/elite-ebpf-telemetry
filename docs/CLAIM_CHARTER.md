# Elite Claim Charter (server category)

**Status:** Binding for docs, README, OPS scorecards, and server proofs.  
**Author:** Abdullah Hanif

## Allowed claim (only after gates PASS)

> On production server, among named bakeoff peers on the frozen physics-speed Soft closed-loop rubric, Elite leads for single-node/VPS co-resident workloads: lowest agent overhead + live `elite_predict_*` → Soft DCIC actuate + (when proven) ECGF posture vs static envelope.

Short form (README): `server physics-speed Soft closed-loop VPS bakeoff` with link to [SERVER_CATEGORY_SCORECARD.md](SERVER_CATEGORY_SCORECARD.md).

Verdict tags that may appear after evidence:

| Tag | Meaning |
|-----|---------|
| `SERVER_PHYSICS_VPS_PASS` | Phase 1 LIVE + Phase 2 bakeoff PASS + score ≥90 |
| `SERVER_PHYSICS_VPS_PARTIAL` | Score high but LIVE/H6 incomplete |
| `SERVER_PHYSICS_VPS_UNVERIFIED` | Published before re-proof |
| `ECGF_BENCH_PASS` | B2 ≥ B1 security and ΔCPU ≤ 0.05 cores |
| `ECGF_BENCH_INCONCLUSIVE` | Default until benches say otherwise |
| `CATEGORY_BAKEOFF_PASS` | Named peers beaten on same production server |

## Forbidden forever

- “#1 eBPF in the world” / “best eBPF overall” / “number one kernel”
- “Better than Cilium / Tetragon / Falco / Pixie / Parca” as overall products
- Novel BPF / world-first invention claims (ADR-003)
- Scoring MOCK decision bus alone as live predictive **15/15**
- Silent H6 SKIP counted as closed-loop win
- Vendor hostnames in reports or docs

## Predictive scoring freeze

| Evidence | Max predictive pts |
|----------|-------------------:|
| `H11_PASS_LIVE` (`elite_predict_*` scrape) | 15 |
| Soft DCIC metric delta only (`H11_PASS_DCIC_ONLY`) | 8 |
| MOCK bus only (`H11_PASS_BUS`) | ≤5 |
| Neither runtime | 0 |

## Anti-fraud grep

Docs and README must not contain unscoped phrases:

- `best in the world`
- `number one eBPF`
- `#1 eBPF`
- `world best`, `holy grail`, `staff engineer`, `proven superior`, `independent auditor`

Unless the same sentence also contains `SERVER_PHYSICS_VPS` or `server` + `bakeoff` / `physics-speed`.

Gate script: [scripts/oneclick/claim-charter-grep.sh](../scripts/oneclick/claim-charter-grep.sh).
