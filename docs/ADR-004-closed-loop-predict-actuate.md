# ADR-004: Closed-loop observe → math predict → low-level actuate

## Status

Accepted

## Context

Elite already ships physics exporters (CO-RE + OSS Physics Pack), a userspace EWMA forecaster (`pkg/forecaster`), and Soft DCIC (`pkg/dcic` cgroup v2). Operators need a **single server/VPS closed loop**: fuse network + LLC + PSI signals, project faults with deterministic math, then actuate soft (cgroup) or hard (resctrl) isolation — without claiming “world’s first eBPF” or shipping heavy APM stacks by default.

## Decision

1. **Observe (physics / low-level):** Elite `:9102`, ebpf_exporter `:9435`, optional LLC PERF sensors (`elite_llc_*`), PSI from `/proc/pressure`.
2. **Predict (math only):** multi-signal EWMA + velocity/acceleration + kinematic projection `s + v·t + ½a·t²`; flap floor; causal argmax → `elite_predict_fault_cause` (`network|llc|psi|mixed`). **No ML.**
3. **Actuate (low-level):** Soft DCIC cgroup `cpu.max` always; resctrl L3 CAT only when capability gate says Track B; forecaster `semi` sheds event probes only for network/mixed causes.
4. **One-click profiles:** `scripts/oneclick/elite-oneclick.sh` + `profiles.env` — Core = `closed-loop`; heavy compose (OBI/Parca/…) = optional profiles only.
5. **Shared decision path:** Soft DCIC may consume predict fault gauges; avoid a second independent EWMA “brain” for the same trip.

## Explicitly rejected

- Fake “world’s first eBPF” marketing.
- Default-on OBI/Parca/Tetragon/Hubble on server.
- NOSONAR / Quality Gate waivers.
- Touching co-resident PM2 process sets.

## Consequences

- Working Mode DoD + after-working test suite gate every wave.
- Scorecard may report `SOFT_ONLY` as success when hardware lacks resctrl.
- Attribution for every composed upstream remains mandatory (ADR-003).

## Verify

```bash
sudo bash scripts/oneclick/elite-oneclick.sh install --profile closed-loop
bash scripts/oneclick/elite-oneclick.sh test --suite after-working
```
