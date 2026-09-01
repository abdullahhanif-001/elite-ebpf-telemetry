# Issue #1202 Reply — Ready to Post

**Status:** Evidence committed — `docs/evidence/scx-1202/CHALLENGE_PROOF_20260901/`  
**Verdict:** `LINUX_EBPF_CHALLENGE_PASS fail=0` + `ANDREA_PROOF_PASS fail=0`

Post at: https://github.com/sched-ext/scx/issues/1202#issuecomment-new

---

Hi @arighi,

We built a full challenge proof suite on our sched_ext proof host (kernel 6.19-rc7). This answers your question on PR #3780: **ext_server + SCX_ENQ_REIMED is necessary but not sufficient.**

**Evidence (public repo):**

- Bundle: [CHALLENGE_PROOF_20260901](https://github.com/abdullahhanif-001/elite-ebpf-telemetry/tree/main/docs/evidence/scx-1202/CHALLENGE_PROOF_20260901)
- Andrea A/B report: `tier2/ANDREA_PROOF_REPORT.md`
- Static verify: `bash scripts/verify-scx-1202-evidence.sh`

**Side-by-side (same host):**

| Arm | Test | Result |
|-----|------|--------|
| C | `rt_stall` kselftest | EXT >= 4% — L1 ext_server confirmed |
| A | bpfland without `scx_rt_guard` + RT stress | Documented #1202 mechanism |
| B | `rt_guard_stress` 60s soak | PASS — no stall with L3 |

**Reproduce on sched_ext host:**

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_LITE_MODE=1
bash scripts/contabo/run-challenge-finish-lite.sh
```

Layer 3 (`scx_rt_guard.bpf.h`) complements ext_server on the `sched_switch` reenqueue path via `scx_bpf_reenqueue_local()`.

We will reopen the upstream PR when you are ready to review.

— Abdullah
