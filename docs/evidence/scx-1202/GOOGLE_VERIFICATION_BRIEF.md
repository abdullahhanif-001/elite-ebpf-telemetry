# SCX#1202 — Google / Interview Verification Brief

**Author:** Abdullah Hanif  
**Date:** 2026-09-01 (updated)  
**Claim level:** Verified fix on sched_ext kernel; full challenge proof suite; upstream merge pending

---

## 1. Problem

[sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202) — RT tasks monopolize CPU → EXT scheduler runnable tasks stall → kernel watchdog ejects BPF scheduler with `SCX_EXIT_ERROR_STALL` (false positive).

## 2. Your contribution

Three-layer fix:

| Layer | Component | Your work |
|-------|-----------|-----------|
| L1 | ext_server DL server | Tested on VPS (Andrea Righi branch) |
| L2 | RT-aware watchdog (`scx_stall_caused_by_rt`) | Authored patch for LKML |
| L3 | `scx_rt_guard.bpf.h` BPF interceptor | Authored header + selftests + upstream PR |

Also built verification gates: SCX#1202 matrix H1–H12, `RT_GUARD_PASS`, full challenge proof suite (D1–D6 + T1–T4).

## 3. Proof (reproducible)

**Static verify (any laptop, 30 seconds):**

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
bash scripts/verify-scx-1202-evidence.sh
# → SCX1202_EVIDENCE_VERIFY=PASS
```

**Full challenge proof (sched_ext host only):**

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash scripts/contabo/run-linux-ebpf-challenge-proof.sh
# → LINUX_EBPF_CHALLENGE_PASS fail=0
# → docs/evidence/scx-1202/CHALLENGE_PROOF_<date>/
```

**Q&A playbook:** [CHALLENGE_QA_PLAYBOOK.md](CHALLENGE_QA_PLAYBOOK.md) — any reviewer question → command → evidence file.

**Prior evidence bundle:** [VERIFICATION_20260901-045612/](VERIFICATION_20260901-045612/)

| Verdict | Result |
|---------|--------|
| `RT_GUARD_PASS` | `fail=0` |
| `HOLY_GRAIL_1202_SOLVED` | `YES` 12/12 |
| `GLOBAL_EBPF` | `fail=0` |
| `RT_GUARD_FLOOD` | `fail=0` |
| `ANDREA_PROOF_PASS` | Arms C/A/B (Tier 2) |
| `LINUX_EBPF_CHALLENGE_PASS` | T1–T4 master |

**Live (sched_ext host only — not valid on generic 6.8 kernels):**

```bash
ssh ##### 'export REAL_ONLY=1 ELITE_SRC=/opt/elite/src && \
  bash scripts/contabo/run-linux-ebpf-challenge-proof.sh 1 | tail -5'
```

## 4. Upstream status

| Item | Link | Status |
|------|------|--------|
| Layer 3 PR | https://github.com/sched-ext/scx/pull/3780 | CLOSED (dev) — reopen after challenge PASS |
| Issue #1202 | https://github.com/sched-ext/scx/issues/1202 | OPEN |
| Layer 2 LKML | [LKML_SUBMISSION.md](LKML_SUBMISSION.md) | Ready to send |

**Fully resolved upstream** = PR merged + #1202 closed. Not claimed until then.

## 5. What NOT to claim

- No Google VRP / bug bounty for kernel sched_ext
- Do not say "fully resolved upstream" before merge
- Do not use DigitalOcean 6.8 VPS for SCX gate claims

## 6. Known limitations (pre-disclosed)

- **IND-SCX-001:** L3 reenqueues on every RT `sched_switch`; 60s soak passes; scale perf TBD
- **IND-SCX-002:** L2 skips `scx_partial_switch`; FAIR-only hogging edge case documented

## 7. 10-minute demo script

1. Run `verify-scx-1202-evidence.sh` → PASS  
2. Show `CHALLENGE_QA_PLAYBOOK.md` — pick any question, run command, show verdict  
3. Walk Andrea A/B: `tier2/ANDREA_PROOF_REPORT.md`  
4. Optional: live proof host `run-linux-ebpf-challenge-proof.sh --tier 1`  
5. Walk through `contrib/sched-ext/bpf/scx_rt_guard.bpf.h`

---

*For maintainers: evidence is independent of author claims — verifier script is in public repo.*
