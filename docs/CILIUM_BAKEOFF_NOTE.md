# Cilium Same-Host Bakeoff — Documented Procedure (Not Marketing)

**Purpose:** Measure policy→kernel latency and thundering-herd outcome on one host with Cilium agent vs Elite.

## Elite (this repo)

```bash
bash benchmarks/contabo-gates/w4-xdp-inject-latency.sh
bash scripts/oneclick/thundering-herd-proof.sh
```

## Cilium (optional same host)

Install Cilium agent per upstream docs (no full CNI required for map latency class comparison). Measure time from policy CRD update to dataplane map visible — typically ms–tens of ms class per W4 report matrix.

## Honest claim boundary

Document measured numbers in `scripts/oneclick/results/*-latest.txt`. Do **not** claim "beats Cilium overall" — Elite axis is **predictive VPS systemd closed-loop + sub-µs map sync path**.
