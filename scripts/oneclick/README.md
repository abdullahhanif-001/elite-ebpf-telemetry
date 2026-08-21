# Elite One-Click Physics Pack

Compose proven GitHub eBPF exporters — **no scratch kernel inventions**.

## Contabo / VPS (one command)

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

Pinned env: [`versions.env`](versions.env). Attribution: [`ATTRIBUTION.md`](ATTRIBUTION.md).

## Prometheus / Grafana

- Merge [`prometheus-scrape.yml`](prometheus-scrape.yml) into Prometheus `scrape_configs`.
- Import [`grafana-elite-physics-pack.json`](grafana-elite-physics-pack.json).

## Kubernetes

See [`k8s-oneclick.md`](k8s-oneclick.md) for Retina / KubeSkoop / Gadget one-liners.

## ADR

[`docs/ADR-003-oneclick-oss-compose.md`](../../docs/ADR-003-oneclick-oss-compose.md)
