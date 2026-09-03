# Elite One-Click Physics Pack

Compose proven GitHub eBPF exporters — **no scratch kernel inventions**.

## Profiled install (recommended)

```bash
sudo bash scripts/oneclick/elite-oneclick.sh install --profile predict
sudo bash scripts/oneclick/elite-oneclick.sh install --profile closed-loop
bash scripts/oneclick/elite-oneclick.sh status
bash scripts/oneclick/elite-oneclick.sh test --suite after-working
bash scripts/oneclick/elite-oneclick.sh test --suite heavy
```

Profiles: `minimal`, `physics`, `predict`, `llc`, `dcic-soft`, `closed-loop`, `compose-*` (optional heavy). Knobs: [`profiles.env`](profiles.env). ADR: [`docs/ADR-004-closed-loop-predict-actuate.md`](../../docs/ADR-004-closed-loop-predict-actuate.md). Heavy gates write [`HEAVY_TEST_SCORECARD.md`](HEAVY_TEST_SCORECARD.md).

## Server / VPS (physics pack only)

```bash
sudo bash scripts/oneclick/elite-physics-pack.sh install
bash scripts/oneclick/physics-pack-proof.sh
```

Requires: Linux, root, BTF (`/sys/kernel/btf/vmlinux`), Elite agent already on `:9102` (or install via `./install.sh --mode metal`).

## What gets installed

| Port | Component | Source pin |
| --- | --- | --- |
| 9102 | Elite agent (you already run) | this repo |
| 9435 | Cloudflare ebpf_exporter + examples | `v2.5.1` |
| 2224 | Inspektor Gadget metrics (optional) | `v0.55.1` |
| 9103 | Soft DCIC (profile `dcic-soft` / `closed-loop`) | this repo |
| 9104 | LLC PERF sensors (profile `llc` / `closed-loop`) | this repo |

Pinned env: [`versions.env`](versions.env). Attribution: [`ATTRIBUTION.md`](ATTRIBUTION.md). Optional compose: [`compose/`](compose/).

## Prometheus / Grafana

- Merge [`prometheus-scrape.yml`](prometheus-scrape.yml) into Prometheus `scrape_configs`.
- Import [`grafana-elite-physics-pack.json`](grafana-elite-physics-pack.json).

## Kubernetes

See [`k8s-oneclick.md`](k8s-oneclick.md) for Retina / KubeSkoop / Gadget one-liners.

## ADR

- [`docs/ADR-003-oneclick-oss-compose.md`](../../docs/ADR-003-oneclick-oss-compose.md)
- [`docs/ADR-004-closed-loop-predict-actuate.md`](../../docs/ADR-004-closed-loop-predict-actuate.md)
