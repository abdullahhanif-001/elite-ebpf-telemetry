# Maintainer Reply Pack — SCX#1202 (@arighi)

**Use after:** `LINUX_EBPF_CHALLENGE_PASS fail=0` on sched_ext proof host + committed `CHALLENGE_PROOF_<date>/`

Post as reply on: https://github.com/sched-ext/scx/issues/1202

---

## English reply (copy-paste)

Hi @arighi,

Thank you for the question on PR #3780 — we paused that PR while finishing the full verification suite. Here is the evidence-backed answer.

**We agree** ext_server + SCX_ENQ_REIMED is **necessary**. Our `rt_stall` kselftest shows EXT tasks receive ≥4% CPU under RT load on the same kernel (Arm C in our challenge proof). That confirms L1 works.

**It is not sufficient alone** for the #1202 repro path. Stock schedulers like bpfland do not include `scx_rt_guard.bpf.h`. When RT monopolizes a CPU, the sched_switch reenqueue path is separate from deadline-server enqueue — that is exactly what Layer 3 addresses via `scx_bpf_reenqueue_local()` on RT/FIFO/RR/DEADLINE `sched_switch`.

**Side-by-side proof (same proof host, kernel 6.19-rc7 + sched_ext):**

| Arm | Test | Result |
|-----|------|--------|
| C | `rt_stall` | EXT ≥ 4% — L1 confirmed |
| A | bpfland without rt_guard + RT stress | Documented #1202 mechanism (see report) |
| B | `rt_guard_stress` 60s soak | PASS — no stall with L3 |

**Reproduce:**

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
bash scripts/verify-scx-1202-evidence.sh   # static check
# On sched_ext host:
bash scripts/contabo/run-linux-ebpf-challenge-proof.sh
```

**Evidence:** `docs/evidence/scx-1202/CHALLENGE_PROOF_<date>/`  
**Q&A:** `docs/evidence/scx-1202/CHALLENGE_QA_PLAYBOOK.md`

We will reopen the upstream PR when the maintainer team is ready to review the full gate matrix.

---

## Do NOT post until

- [x] `LINUX_EBPF_CHALLENGE_PASS fail=0` in committed bundle
- [x] `ANDREA_PROOF_PASS fail=0`
- [x] G6 no SKIP (`SOAK_PASS LOADER=bpfland`)
- [x] `bash scripts/verify-scx-1202-evidence.sh` exits 0

**Ready:** See [ISSUE_1202_REPLY_READY.md](ISSUE_1202_REPLY_READY.md)

---

## Reopen upstream PR checklist

1. Push latest `contrib/sched-ext/bpf/scx_rt_guard.bpf.h` + selftests
2. Link `CHALLENGE_PROOF_<date>/` in PR body
3. Reference this reply on #1202
4. Tag @arighi, @tejun, @kdump
