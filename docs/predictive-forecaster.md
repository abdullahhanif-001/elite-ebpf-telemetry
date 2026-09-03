# Deterministic Predictive Observability (userspace)

Pure-math EWMA + velocity/acceleration forecaster in `pkg/forecaster`. **No ML. No new eBPF.** Built as an always-on sidecar loop inside `elite-agent`, not a notebook prototype.

## Problem

Kernel physics gauges (`softirq_wait_seconds`, socket latency, …) tell you what *already* hurt. Operators on a busy VPS need a **bounded-cost** signal that trips *before* hard latency, without allocating every scrape tick and without flapping on noise.

## Pipeline

```text
loopback Prometheus text
        │
        ▼
 Scraper (reuse buffers, []byte prefix match, fixed counter slots)
        │  one scalar latency sample / interval
        ▼
 Engine  ring(8) → EWMA(α=0.3) → vel / acc → project horizon
        │
        ▼
 Runner  double-buffer Snapshot → Collector (elite_predict_*)
        │
        └─ mode=semi → EventShedder (shed event probes, keep metrics)
```

### Projection (when accelerating)

```text
projected = ewma + velocity*horizon + 0.5*acceleration*horizon^2
```

Default horizon = 5s. Fault if `projected >= hardDrop` **and** current EWMA `>= 0.3 * hardDrop` (or if EWMA already ≥ hardDrop). The 30% floor cuts flap false positives while still catching real surges within one sample interval.

Defaults: α=`0.3`, window=`8`, hardDrop=`0.1s`, accThreshold=`0.001 s^-2`, interval=`1s`.

## Hot-path constraints (why this is not a weekend script)

- **0 allocs/op** targets on `ParseBody` / `Observe` (verified with `go test -benchmem` under Docker on server).
- Scraper: 256 KiB reusable body + read buffers; `DisableCompression`; no per-tick `map` for series.
- Runner: `[2]Snapshot` flip via `atomic.Uint32` index — avoids allocating a new pointer each tick.
- Semi mode uses the agent’s existing Reload path to shed **event** probes only; metrics probes stay registered.

## Enable

```yaml
forecast:
  enabled: true
  interval: 1s
  horizon: 5s
  mode: dry-run   # or semi
  hardDropSeconds: 0.1
  targets:
    - url: "http://127.0.0.1:9435/metrics"
      series: ["softirq_wait_seconds"]
    - url: "http://127.0.0.1:9102/metrics"
      series: ["elite_socketlatency"]
```

- **dry-run:** Warn logs + `elite_predict_*` only.
- **semi:** also sheds event probes for `semiCooldown`, then restores.

## Metrics

| Series | Meaning |
|--------|---------|
| `elite_predict_latency_ewma_seconds` | Smoothed latency |
| `elite_predict_velocity` | EWMA rate (s/s) |
| `elite_predict_acceleration` | EWMA acceleration (s/s²) |
| `elite_predict_projected_5s_seconds` | Kinematic projection at horizon |
| `elite_predict_fault` | 1 when fault logic trips |
| `elite_predict_faults_total` | Fault counter |

## Verify

```bash
go test ./pkg/forecaster/ -count=1
go test ./pkg/forecaster/ -bench=. -benchmem -count=1
bash scripts/oneclick/forecaster-agrade.sh   # Server, PM2-safe
curl -s 127.0.0.1:9102/metrics | grep elite_predict_
```

Gate file: [`scripts/oneclick/SCORECARD_SWITCH.md`](../scripts/oneclick/SCORECARD_SWITCH.md). Marketing may claim VPS switch-readiness **only** when `VERDICT=SWITCH_READY`.

## What this is not

- Not XDP packet steering, not an in-kernel ML classifier, not a replacement for Retina/Hubble CNI plugins.
- Honest adjacent work: OSS Physics Pack compose (ADR-003) + this userspace predictor on top of existing Elite CO-RE probes.
