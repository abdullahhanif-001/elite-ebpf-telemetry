# Release v0.9 — Zero-Buffer Overload Controller

## Highlights

- TrafficEngine: λ/ρ kinematic projection from `elite_tcpsummary_*`
- Graduated XDP shedding via `shed_ppm` (policy map v2)
- One-click: `bash scripts/oneclick/elite-zero-buffer-complete.sh`
- Microsoft review pack: `docs/MICROSOFT_REVIEW_PACK.md`

## Verify

```bash
go test ./pkg/forecaster/ ./pkg/elitecontroller/ -count=1
bash scripts/oneclick/elite-zero-buffer-complete.sh  # on VPS with Elite installed
```

## Tag (maintainer)

```bash
git tag -a v0.9.0-zero-buffer -m "Zero-buffer overload controller Track D"
```
