# ADR-005: Track C — ECGF-lite (Physics-Triggered Security Posture)

## Status

Proposed

## Context

Ultra invention research rejected novel BPF, Tetragon clones, Sandlock clones, and semantic prompt firewalls (see `docs/research/PRIOR_ART_MATRIX.md`). The surviving gap is coupling Elite’s kinematic/physics predict path to **dynamic** Soft DCIC + consequence-envelope posture on Contabo/VPS.

## Decision

1. Ship **ECGF-lite** as userspace `elite-ecgf` + envelope scripts — **no new Elite `bpf/` programs**.
2. Do **not** supersede ADR-003 or ADR-004.
3. Honesty gate: MOCK decision bus alone is **not** live predict PASS.
4. Superiority default: `NOT_PROVEN_SUPERIOR` until B2 vs B1 benches.

## Consequences

- Optional profile feature `ecgf`.
- Red-team + bench scripts required before marketing language.
- If MVP equals static Sandlock+cgroup, demote to product feature.

## Rejected (this ADR)

Novel BPF inventions, Tetragon replacement, Falco ruleset, AgentCgroup/sched_ext clone, prompt semantic defense, software-only LLC control.
