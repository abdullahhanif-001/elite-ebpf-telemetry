# ADR-003: Elite One-Click OSS Compose (No Scratch Kernel Inventions)

## Status

Accepted

## Context

Building novel kernel BPF (packet fate ledgers, in-kernel MM→Net causal graphs, probe-cost meters, hook tournaments) duplicates industry work and is slow to ship. Prior art already covers softirq latency, `kfree_skb` reasons, shrink latency, XDP counters, and K8s drop plugins (Cloudflare ebpf_exporter, Inspektor Gadget, Microsoft Retina, Alibaba KubeSkoop).

## Decision

**Elite Physics Pack** is an **integrator**, not a scratch BPF invention lab:

1. Keep Elite agent as the home-base `elite_*` exporter (KubeSkoop lineage).
2. Install pinned GitHub release binaries / apt packages only via `scripts/oneclick/`.
3. Default VPS stack:
   - Elite `:9102`
   - Cloudflare `ebpf_exporter` `:9435` with prebuilt examples: softirq-latency-net-rx, kfree_skb, tcp-retransmit, udp-drops, shrinklat
   - Inspektor Gadget `ig` (optional tcpdrop metrics `:2224`)
   - `bpfcc-tools` for CLI softirq/tcpdrop helpers
4. K8s path documents upstream one-liners (`skoopbundle.yaml`, Retina Helm, `kubectl gadget deploy`) — no Retina fork into Elite.
5. Uniqueness claim = **packaged server/VPS + K8s compose + Grafana scorecard under Elite branding**, with mandatory attribution (`scripts/oneclick/ATTRIBUTION.md`).

## Explicitly rejected

- New Elite-authored `bpf/fate_ledger.c`, MM→Net causal BPF, self-metering probe BPF, hook tournament engines marketed as “world first”.
- Claiming first XDP / first per-CPU map / first in-kernel AI / first self-heal.

## Consequences

- Faster Server proof cycles; license/attribution obligations for every upstream.
- Product roadmap = pin versions, scrape glue, scorecard, soak — not verifier wrestling for novel programs.
- Optional netstacklat YAML is vendored by commit SHA but **not** auto-started (requires upstream build).

## Pins

See [`scripts/oneclick/versions.env`](../scripts/oneclick/versions.env).

## Verify

```bash
sudo bash scripts/oneclick/elite-physics-pack.sh install
bash scripts/oneclick/physics-pack-proof.sh
```
