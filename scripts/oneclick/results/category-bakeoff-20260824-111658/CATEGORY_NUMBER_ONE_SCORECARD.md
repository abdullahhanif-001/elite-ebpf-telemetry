# Category Number One Scorecard

**Generated:** 2026-08-24T11:17:10+02:00
**Host out:** `/opt/elite/src/scripts/oneclick/results/category-bakeoff-20260824-111658`

See [CLAIM_CHARTER.md](CLAIM_CHARTER.md).

```text
ELITE_CATEGORY_NUMBER_ONE
elite_cpu_median=0.046667
elite_rss_mb_median=94.6
node_cpu_median=na
node_rss_mb_median=na
live_predict=1
soft_dcic=1
node_exporter_present=0
VERDICT=CATEGORY_BAKEOFF_PASS
reasons=none
```

| Peer | CPU cores (median) | RSS MB | Soft actuate | Live predict |
|------|-------------------:|-------:|:------------:|:------------:|
| Elite closed-loop | 0.046667 | 94.6 | yes | yes |
| P-node (node_exporter) | na | na | no | no |
| P-static (forecast off) | n/a this run | n/a | no | no |
| P-open (no Soft DCIC) | n/a this run | n/a | no | n/a |

**Win rule applied:** Elite must expose elite_predict_* + Soft DCIC metrics and keep median agent CPU <= 0.05 cores; node_exporter compared when present (capability: Soft actuate + live predict).
