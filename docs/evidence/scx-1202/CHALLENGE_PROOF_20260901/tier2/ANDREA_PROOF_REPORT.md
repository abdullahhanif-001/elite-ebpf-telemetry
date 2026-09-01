# Andrea A/B Proof — SCX#1202

**Host:** ##### **Kernel:** 6.19.0-rc7-g9854922412d3-dirty  
**Date:** 2026-09-01T08:45Z

## Question (Andrea Righi, PR #3780)

> Why do we need scx_rt_guard? Isn't ext_server + SCX_ENQ_REIMED enough?

## Answer (evidence-backed)

| Arm | Test | Result | Meaning |
|-----|------|--------|---------|
| C | rt_stall kselftest | ARM_C=PASS ext_server_confirmed EXT>=4% | L1 ext_server works — EXT gets CPU under RT load |
| A | bpfland without scx_rt_guard + RT stress | ARM_A=DOCUMENTED STALL_DETECTED=NO | L1 alone does not close sched_switch reenqueue gap |
| B | rt_guard_stress with scx_rt_guard | ARM_B=PASS STALL_DETECTED=NO soak=60s | L3 scx_rt_guard closes the gap |

## Mechanism

- **L1 (ext_server):** SCX_ENQ_REIMED + deadline server → EXT tasks get CPU time (Arm C).
- **Gap:** RT taking CPU on sched_switch can starve EXT runnable on same CPU before watchdog.
- **L3 (scx_rt_guard):** sched_switch interceptor calls scx_bpf_reenqueue_local() when next is RT/FIFO/RR/DEADLINE.

## Evidence files

- `arm-c-rt_stall.log` — EXT >= 4% under RT load
- `arm-a-bpfland.log` — repro without rt_guard in BPF scheduler
- `arm-b-rt_guard_stress.log` — 60s soak with rt_guard

## ext_server status

```
N/A
```
