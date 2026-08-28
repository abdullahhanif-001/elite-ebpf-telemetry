# Heavy Engineer Test Scorecard

**Repository:** [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)  
**Generated:** 2026-08-24T07:45:12+02:00 (Contabo) / Sonar re-polled after push  
**Host:** production VPS (hostname redacted)  
**Out dir:** `/tmp/elite-heavy-vps-20260824-073310`  
**HEAD:** `a66a8a0` (+ CI follow-up for check workflow)

```text
ELITE_HEAVY_SUITE
fail_count=0
skip_count=5
soft_only=0
sonar_key=abdullahhanif-001_elite-ebpf-telemetry
sonar_alert_status=OK
VERDICT=HEAVY_PASS
```

## Gate results

```text
[H7a] PASS: PM2 guard before
[H0a] PASS: bash -n oneclick scripts
[H0b] SKIP: shellcheck not installed
[H1] PASS: go test forecaster/dcic/llc/export/exporter
[H2] PASS: go test -race forecaster/dcic/llc
[H3] PASS: Observe path 0 B/op / 0 allocs/op
[H4] PASS: MOCK_ decision bus + causal goldens (pkg tests)
[H5] PASS: after-working exit 0
[H6a] SKIP: physics-pack-proof.sh failed/optional
[H6b] SKIP: llc-pack-proof.sh SKIP (capability)
[H6c] SKIP: soft-dcic-verify.sh SKIP (capability)
[H8a] PASS: build elite-agent
[H8b] PASS: build elite-dcic
[H8c] PASS: build elite-llc-sensors
[H7b] PASS: PM2 guard after
[H9] PASS: Sonar alert_status=OK (post-push)
[H10] PASS: Elite CI success on main (post-push)
```

## Notes

- Contabo run kept PM2 untouched (`PM2_GUARD_OK` before/after).
- Soft/capability SKIPs are expected when LLC/DCIC exporters are not installed on the VPS.
- Go module path stays `github.com/alibaba/kubeskoop` (fork convention); public brand is `abdullahhanif-001/elite-ebpf-telemetry`.

## Bench excerpt

```text
BenchmarkCompeteEngineObserveNS-4    11200256        108.2 ns/op         0 B/op        0 allocs/op
BenchmarkEngineObserve-4             13359013         95.85 ns/op        0 B/op        0 allocs/op
BenchmarkParseBodyFlood-4                1344     873739 ns/op     217.52 MB/s         0 B/op        0 allocs/op
BenchmarkParseMetricLineBytes-4      22153615         54.46 ns/op        0 B/op        0 allocs/op
ok  github.com/alibaba/kubeskoop/pkg/forecaster 5.518s
```
