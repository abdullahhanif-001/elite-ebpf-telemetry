# Thundering Herd Proof — Elite Zero-Buffer Controller

## Problem

Reactive autoscalers and load balancers scale **after** kernel queues fill. Thundering herd: connection-rate λ spikes before latency EWMA rises.

## Physics model

```text
λ_ewma from elite_tcpsummary_tcpestablishedconn
ρ_proj = (λ_ewma + v·h + ½a·h²) / μ_est
overload = clamp((ρ_proj - ρ_target)/(1 - ρ_target), 0, 1)
shed_ppm = overload^γ · 1_000_000
```

## Reproduce

```bash
export ELITE_XDP_IFACE=lo ELITE_XDP_MODE=skb
bash scripts/oneclick/elite-zero-buffer-complete.sh
```

Or stepwise:

```bash
bash benchmarks/thundering-herd/run.sh
bash scripts/oneclick/thundering-herd-proof.sh
```

## Pass criteria (G8)

- `THUNDERING_HERD_PASS` in `scripts/oneclick/results/thundering-herd-proof-latest.txt`
- Agent RSS ≤ 110% of baseline under synthetic spike (`benchmarks/thundering-herd/run.sh`)

## Artifacts

| File | Content |
|------|---------|
| `scripts/oneclick/results/thundering-herd-proof-latest.txt` | Gate verdict |
| `logs/thundering-herd-bench-latest.txt` | RSS before/after |

## Honest limits

- One-hop `XDP_REDIRECT` spillover only — not Maglev / Azure LB replacement.
- Proofs default to `lo` interface to avoid SSH brick on `eth0`.

## Cilium comparison (documented, not marketing)

Measure policy→map latency via W4 gate (`benchmarks/server-gates/w4-xdp-inject-latency.sh`) on same host. Thundering outcome compared qualitatively in staff reports — Elite targets **predictive admission** not CNI dataplane replacement.
