# Architecture — ECGF-lite (Physics-Triggered Security Posture)

**Status:** PROPOSED DESIGN (Track C)  
**BPF:** none new (ADR-003)

```text
elite-agent :9102 ──► forecaster ──► decision bus JSON
ebpf_exporter/LLC/PSI ─┘                    │
                                            ▼
                                   elite-ecgf :9105
                          posture: observe|tighten|isolate
                           │                    │
                           ▼                    ▼
                    Soft DCIC :9103      envelope profiles
                    (BE quota/advise)    (seccomp/systemd/Landlock)
```

## Components

1. **PostureController** (`pkg/ecgf`, `cmd/elite-ecgf`) — 1 Hz loop; reads decision bus; exports `elite_ecgf_posture`.
2. **Envelope runner** (`scripts/oneclick/ecgf-envelope.sh`) — launches MOCK agent under Restrict* / seccomp / Landlock when available.
3. **Soft DCIC** — EXISTING; ECGF may write BE quota hint file consumed by advise/enforce modes.

## Fail modes

- Decision bus missing → posture `observe` (fail-open for density; fail-closed for envelope sticky flag).
- Kernel without Landlock → document SKIP for A2 path checks; use systemd ProtectHome/PrivateTmp.
