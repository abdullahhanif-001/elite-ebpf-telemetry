# Linux + eBPF + SCX#1202 Challenge Proof (Lite)

**Date:** 2026-09-01  
**Host:** ##### (sched_ext proof host 4vCPU / 8GB)  
**Kernel:** 6.19.0-rc7 + sched_ext  
**Mode:** `FLOOD_LITE_MODE=1` (short flood; full repro unchanged)

## Master verdict

```
LINUX_EBPF_CHALLENGE_PASS fail=0 mode=lite
```

## Tier verdicts

| Tier | Gate | Result |
|------|------|--------|
| T1 | RT_GUARD_PASS | fail=0 |
| T1 | #1202 repro | STALL_DETECTED=NO |
| T2 | Andrea A/B | ANDREA_PROOF_PASS fail=0 |
| T2 | Flood P1-P5 | RT_GUARD_FLOOD_PASS fail=0 |
| T3 | SCX#1202 matrix H1–H12 | HOLY_GRAIL_1202_SOLVED=YES 12/12 |
| T4 | Global eBPF | fail=0 |

## Reproduce

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_LITE_MODE=1
bash scripts/contabo/run-challenge-finish-lite.sh
bash scripts/verify-scx-1202-evidence.sh
```

## Note on lite flood

Flood phases use shorter cooldowns and skip per-scheduler ftrace soaks on small VPS. **Reproduction tests are full:** G0-G6, rt_stall, rt_guard_stress 60s, Andrea Arms C/A/B, bpfland 5min soak (G6).
