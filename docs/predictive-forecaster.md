# Deterministic Predictive Observability (userspace)

Pure-math EWMA + velocity/acceleration forecaster in `pkg/forecaster`. **No new eBPF.**

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

- **dry-run:** Warn logs + `elite_predict_*` metrics only.
- **semi:** also sheds event probes for `semiCooldown`, then restores (metrics probes stay up).

## Verify

```bash
go test ./pkg/forecaster/ -count=1
go test ./pkg/forecaster/ -bench=. -benchmem -count=1
bash scripts/oneclick/forecaster-agrade.sh   # Contabo, PM2-safe
curl -s http://127.0.0.1:9102/metrics | grep elite_predict_
```

Retina-beat scorecard: [`scripts/oneclick/SCORECARD_SWITCH.md`](../scripts/oneclick/SCORECARD_SWITCH.md) (`VERDICT=SWITCH_READY` required before VPS switch claims).

Series: `elite_predict_latency_ewma_seconds`, `elite_predict_velocity`, `elite_predict_acceleration`, `elite_predict_projected_5s_seconds`, `elite_predict_fault`, `elite_predict_faults_total`.
