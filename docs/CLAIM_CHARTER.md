# Elite Claim Charter (category #1)

**Status:** Binding for docs, README, WORLD scorecards, and Contabo proofs.

## Allowed claim (only after gates PASS)

> On Contabo, among named bakeoff peers on the frozen physics-speed Soft closed-loop rubric, Elite is **#1** for single-node/VPS co-resident workloads: lowest agent overhead + live `elite_predict_*` → Soft DCIC actuate + (when proven) ECGF posture superiority vs static envelope.

Short form (README): `#1 Contabo physics-speed Soft closed-loop VPS bakeoff` with link to [CATEGORY_NUMBER_ONE_SCORECARD.md](CATEGORY_NUMBER_ONE_SCORECARD.md).

Verdict tags that may appear after evidence:

| Tag | Meaning |
|-----|---------|
| `WORLD_BEST_PHYSICS_SPEED_VPS` | Phase 1 LIVE + Phase 2 bakeoff PASS + score ≥90 |
| `WORLD_BEST_PHYSICS_SPEED_SOFT` | Score high but LIVE/H6 incomplete — **not** hard #1 |
| `WORLD_BEST_PROVISIONAL` | Published before re-proof — do not market as hard |
| `ECGF_PROVEN_SUPERIOR` | B2 ≥ B1 security and ΔCPU ≤ 0.05 cores |
| `NOT_PROVEN_SUPERIOR` | Default until benches say otherwise |
| `CATEGORY_BAKEOFF_PASS` | Named peers beaten on same Contabo host |

## Forbidden forever

- “#1 eBPF in the world” / “best eBPF overall” / “number one kernel”
- “Better than Cilium / Tetragon / Falco / Pixie / Parca” as overall products
- Novel BPF / world-first invention claims (ADR-003)
- Scoring MOCK decision bus alone as live predictive **15/15**
- Silent H6 SKIP counted as closed-loop win

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

Unless the same sentence also contains `PHYSICS_SPEED_VPS` or `Contabo` + `bakeoff` / `physics-speed`.

Gate script: [scripts/oneclick/claim-charter-grep.sh](../scripts/oneclick/claim-charter-grep.sh).
