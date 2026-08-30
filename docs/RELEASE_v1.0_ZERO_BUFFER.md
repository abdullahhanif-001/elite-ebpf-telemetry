# Release v1.0.0 — Zero-Buffer Root Solve

## Highlights

- XDP v3: per-src token buckets, port/VIP tiers, PERCPU stats, DEVMAP redirect
- Ringbuf λ events + 50ms forecaster tick + live μ estimator
- Federation push via `elite-controller` (500ms interval)
- Gates G0, G9–G15 + extended one-click orchestrator

## Run proofs

```bash
bash scripts/oneclick/elite-zero-buffer-complete.sh
```

## Docs

- [ADR-007](ADR-007-xdp-v3-admission.md)
- [RCA gaps](RCA_ZERO_BUFFER_GAPS.md)
- [Microsoft pack](MICROSOFT_REVIEW_PACK.md)

## Tag

`v1.0.0-zero-buffer` when G9–G13 pass on staging (`eth0` + health watch).
