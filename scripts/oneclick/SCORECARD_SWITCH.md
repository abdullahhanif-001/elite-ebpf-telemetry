# Elite Switch Scorecard (auto)

Generated: 2026-08-21T10:45:16+02:00

```
ELITE_SWITCH_MOAT
observe_ns/op=97.92
bench_parse_line=BenchmarkParseBodyFlood-4           	    1305	    917809 ns/op	 207.08 MB/s	       0 B/op	       0 allocs/op
flat_false_positives=0
pm2_guard=PASS
live_predict=0
VERDICT=SWITCH_READY
```

## vs Microsoft Retina (honest)

| Dimension | Elite Physics + Forecaster | Microsoft Retina |
| --- | --- | --- |
| Bare VPS one-click | Yes | K8s/Helm primary |
| Predictive 5s fault | Yes (`elite_predict_*`) | Not core claim |
| Drop reason plugins | OSS compose | Native dropreason |
| Always-on CPU proof | This scorecard | DaemonSet varies |

Marketing may claim VPS switch-readiness **only** when `VERDICT=SWITCH_READY`.
