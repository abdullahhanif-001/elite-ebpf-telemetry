# ADR-007: XDP v3 Kernel Admission + Ringbuf Control

**Status:** Accepted  
**Date:** 2026-08-30

## Context

Track D v2 used global `shed_ppm` + 1s userspace loop. Holy grail requires per-packet admission, priority tiers, sub-100ms control, and federation push.

## Decision

1. **Policy map v3 (80B):** `tier_refill_ppm[4]`, `mu_tokens_per_sec`, `rho_proj_ppm`, `escalate_flags`.
2. **Kernel token buckets:** LRU per-src in `elite_src_buckets`; tier from `elite_port_tier` / `elite_vip_lpm`.
3. **Per-CPU stats:** `elite_xdp_stats` as PERCPU_ARRAY.
4. **Ringbuf λ:** `elite_lambda_ring` batch events every 1024 packets.
5. **DEVMAP redirect** for CRITICAL tier overflow; `elite_devmap` pinned.
6. **50ms forecaster** when `policyMapPin` set; ringbuf primary λ path.
7. **Federation push:** `elite-controller` POST to `/internal/forecast/policy`.

## Kill gates

- G9 token bucket pps
- G10 priority tier
- G11 λ leads 50ms
- G12 actuation p99 (W4)
- G13 thundering herd v2
- G14 multicore/native checklist
- G15 federation propagation

## Not in scope

- Full SYN cookie proxy (escalation flags only)
- AF_XDP (stub in contracts/2028-stubs.md)
