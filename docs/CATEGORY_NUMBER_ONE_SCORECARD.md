# Category Number One Scorecard

**Generated:** 2026-08-24T11:17:10+02:00
**Host out:** `/opt/elite/src/scripts/oneclick/results/category-bakeoff-20260824-111658`

See [CLAIM_CHARTER.md](CLAIM_CHARTER.md). Unscoped global eBPF supremacy claims remain forbidden.

## #1 publish gates (all required)

| Gate | Pass criteria | Evidence root |
|------|---------------|---------------|
| G1 Live predict | `H11_PASS_LIVE` — scrape contains `elite_predict_*` | `scripts/oneclick/results/p1-live-*` |
| G2 Soft actuate | Soft DCIC H6 metric delta (SKIP ≠ win) | `scripts/oneclick/results/*` Soft DCIC proof |
| G3 Named bakeoff | `CATEGORY_BAKEOFF_PASS` vs frozen peers on same Contabo host | `category-bakeoff-*` |
| G4 Co-resident | Agent median CPU ≤ 0.05 cores + `PM2_GUARD_OK` | bakeoff + `pm2-guard.sh` |
| G5 Score | World score ≥ 90 → tag `WORLD_BEST_PHYSICS_SPEED_VPS` | [WORLD_BEST_PROVIDER_SCORE.md](WORLD_BEST_PROVIDER_SCORE.md) |

Do **not** set `WORLD_BEST_PHYSICS_SPEED_VPS` in marketing until G1–G5 all PASS from Contabo artifacts (not MOCK bus alone).

## Install UX #1 SLOs (separate lane)

| SLO | Target | Measure |
|-----|--------|---------|
| Cold metal install | ≤ 3 min on Ubuntu 22.04/24.04 Contabo with BTF | `time sudo bash install.sh --mode metal --profile physics` |
| One command | `curl -fsSL …/install.sh \| sudo bash -s -- --profile physics` | No manual `cp` of binaries |
| Auto-update | New `v*` release applied within `check_interval` (default 6h) | `elite-updater` + systemd timer |
| Rollback | One command / auto on failed `/metrics` health | `/opt/elite/bin/previous` + [ROLLBACK.md](../deploy/contabo/ROLLBACK.md) |
| Fail closed | No BTF or kernel &lt; 5.8 → exit ≠ 0 | `install.sh` preflight |

## Last Contabo bakeoff snapshot

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
