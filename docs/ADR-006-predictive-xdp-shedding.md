# ADR-006: Predictive XDP Traffic Shedding (Track D)

**Status:** Accepted  
**Date:** 2026-08-29

## Context

Elite forecaster predicts latency derivatives in userspace (`pkg/forecaster`). `xdp_mitigator` performs binary drop on fault. Thundering herd arrives as connection-rate spikes before latency EWMA trips.

## Decision

1. **Dual-channel kinematics:** latency EWMA + connection-rate λ with ρ projection.
2. **Graduated XDP shedding:** `shed_ppm` in `elite_policy` map (policy_version=2).
3. **Actuate gate:** `actuate` byte must be 1 for XDP drops (set at load via map default).
4. **Global federation:** lightweight `elite-controller` aggregates node overload (Phase 4).

## Map ABI (v2)

```c
struct elite_policy_value {
    __u64 policy_version;   // 2
    __u8  fault;
    __u8  cause;
    __u8  actuate;
    __u8  _pad[5];
    __u64 projected_ns;
    __u64 ewma_ns;
    __u32 overload_ppm;
    __u32 shed_ppm;
    __u32 redirect_ifindex;
};
```

Legacy v1 (32-byte) behavior: binary fault drop when actuate=1.

## Kill gates

- G6 `LAMBDA_LEADS_PASS` — ρ_proj leads latency EWMA under load
- W5 `W5_PASS` — graduated shed, RSS stable
- G8 `THUNDERING_HERD_PASS` — RSS ≤110% baseline under spike

## Microsoft review criteria

- One command repro: `bash scripts/oneclick/elite-zero-buffer-complete.sh`
- Every number → `scripts/oneclick/results/*-latest.txt`

## Not in scope

- Azure Load Balancer / Maglev replacement
- In-kernel ML classifier
- Multi-region Maglev-style LB
