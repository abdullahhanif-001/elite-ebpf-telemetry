# RCA — Zero-Buffer SCX1202 gate matrix Gaps (Track D → v1.0)

**Date:** 2026-08-30  
**Status:** Baseline for v1.0 root solve

## Executive summary

Track D proves **physics + graduated shed** on loopback. It does **not** yet prove line-rate admission, priority tiers, sub-100ms control, or eth0 production path. This document records root causes with file evidence.

## Gap table

| ID | Gap | Root cause | Evidence | v1.0 fix |
|----|-----|------------|----------|----------|
| GAP-1 | Predict-after-queue | 1s scrape interval; λ from established TCP count | [`runner.go`](pkg/forecaster/runner.go) ticker; [`traffic_scraper.go`](pkg/forecaster/traffic_scraper.go) | Ringbuf λ + 50ms tick |
| GAP-2 | Blind shedding | Global `shed_ppm` + prandom, no 5-tuple | [`xdp_mitigator.c`](bpf/xdp_mitigator.c) | Token bucket + tier/port maps |
| GAP-3 | Stats contention | Single ARRAY map, non-atomic struct bump | [`xdp_mitigator.c`](bpf/xdp_mitigator.c) `xdp_bump_stat` | PERCPU_ARRAY stats |
| GAP-4 | Weak redirect | `bpf_redirect(ifidx)` only | [`xdp_mitigator.c`](bpf/xdp_mitigator.c) | DEVMAP + health-aware userspace |
| GAP-5 | Weak herd proof | Agent RSS + bash `/dev/tcp` | [`benchmarks/thundering-herd/run.sh`](benchmarks/thundering-herd/run.sh) | hping3 + conntrack + app RSS |
| GAP-6 | Federation cosmetic | 5s poll, JSON only | [`federate.go`](pkg/elitecontroller/federate.go) | Push model &lt;500ms |

## Measurement checklist (VPS)

Run [`benchmarks/zero-buffer/matrix.sh`](benchmarks/zero-buffer/matrix.sh):

1. `bpftool net show dev lo` / `eth0` — XDP program id, mode (native/skb)
2. `ethtool -i $IFACE` — driver native XDP capability
3. W4 actuation latency artifact
4. W6 token-bucket pps
5. Control-loop lag (λ spike → first drop)

Artifacts land in `scripts/oneclick/results/*-latest.txt`.

## Honest limits

- Single production server ≠ 10M conn/s; multi-node + documented ceiling
- Not Maglev / Azure LB replacement (see [`PLAN_SELF_AUDIT.md`](PLAN_SELF_AUDIT.md))

## Kill criteria

See plan: native XDP unavailable → TC admission fallback; G13 fail on eth0 → lo-only product feature.
