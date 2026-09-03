# Elite Physics Pack — Server scorecard template

Fill after `sudo bash scripts/oneclick/elite-physics-pack.sh install` and a traffic soak.

| Check | Target | Result | Notes |
| --- | --- | --- | --- |
| Elite `/metrics` | `127.0.0.1:9102` | | `curl -sf` + `elite_` series |
| ebpf_exporter `/metrics` | `127.0.0.1:9435` | | softirq_wait / kfree_skb / shrinklat |
| ig metrics (optional) | `127.0.0.1:2224` | | may be absent |
| Elite agent CPU% | `ps` / `top` | | under soak |
| ebpf_exporter CPU% | systemd `CPUQuota=5%` | | |
| Metric loss | scrape gaps | | none expected for counters |

## Vs Retina / Hubble (honest)

| Dimension | Elite Physics Pack (VPS) | Retina | Cilium Hubble |
| --- | --- | --- | --- |
| CNI required | No | No (K8s agent) | Yes (Cilium) |
| One-click VPS | `elite-physics-pack.sh` | Helm/K8s | Cilium install |
| Drop reasons | `kfree_skb` via Cloudflare examples + Elite packetloss | `dropreason` plugin | Hubble drop events |
| Softirq physics | Elite + `softirq-latency-net-rx` | Limited | Limited |
| MM shrink signal | `shrinklat` example | No | No |
| Custom “fate ledger” BPF | Not claimed | Not claimed | Not claimed |

Run automated checks:

```bash
bash scripts/oneclick/physics-pack-proof.sh
```
