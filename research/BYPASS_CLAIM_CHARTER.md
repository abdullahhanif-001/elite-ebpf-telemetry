# Bypass claim charter (kernel / eBPF security research)

This track is **not** Elite product evidence (SCX#1202 gates, `OUR_GOAL.md`, or
`ELITE_OFFLINE=1`). It exists so bypass findings are **live, reproducible, and
honestly classified** — no archived VPS bundles passed off as “today’s lab.”

## Definitions

| Term | Meaning |
|------|---------|
| **SECURITY-IMPACT** | Verifier or kernel accepts a program (or race wins) and you demonstrate **DOS**, **INFO_LEAK**, **OOB**, or **CODE_EXEC** / LPE-relevant behavior with a minimal repro on **this host’s** running kernel. |
| **TEST-INFRA** | Tooling shortcuts (e.g. `patch-scx-ftrace-bypass.py`) that change loader behavior without kernel exploitation. Must be tagged in logs; never filed as a CVE-class bypass. |
| **HYPOTHESIS** | Source audit or userspace-only crash; **no** `BYPASS_CLAIM_VERIFY=PASS`. |
| **USERSPACE** | libbpf/cilium parse or load failure in userspace only; not a kernel verifier bypass unless chained to SECURITY-IMPACT on R1. |

## Forbidden (fail-closed)

1. **`ELITE_OFFLINE=1`** (or any “pass using committed SCX FULL bundle”) for research gates.
2. Citing `docs/evidence/scx-1202/VERIFICATION_*` as proof that **this machine** ran sched_ext.
3. Labeling **TEST-INFRA** patches as security bypasses.
4. **`BYPASS_CLAIM_VERIFY=PASS`** without `00-preflight.json` from the **same** `hostname` + `kernel_release` as the repro run.
5. Product gate strings (`SCX1202_MATRIX_PASS`, `FUTURE_HOLES_PASS`) as research success metrics.

## Required for `BYPASS_CLAIM_VERIFY=PASS`

Layout under `research/claims/<ID>/`:

| File | Content |
|------|---------|
| `MANIFEST.json` | `claim_id`, `impact`, `track` (verifier \| sched_ext \| loader), `status`, `repo_commit` |
| `00-preflight.json` | Output of `scripts/research/live-preflight.sh` on repro host |
| `repro/` | Minimal artifacts (`*.bpf.c`, `*.o`, or shell one-liner) |
| `load.log` | Verifier/load tool output (bpftool, `loadprobe`, dmesg) |
| `dmesg.txt` | Snippet after repro (optional for pure verifier reject bugs) |
| `IMPACT.md` | One page: oracle, negative control, why not a false positive |

**Impact** must be one of: `NONE`, `DOS`, `INFO_LEAK`, `OOB`, `CODE_EXEC`, `USERSPACE`, `HYPOTHESIS`.

**Negative control:** Document a variant that **must** fail (e.g. patched insn, stricter kernel, or `loadprobe` on `negative_reject.bpf.c`).

## Lab tiers

| Tier | Host | Allowed claims |
|------|------|----------------|
| **R0** | Dev VM, no sched_ext | HYPOTHESIS, USERSPACE, verifier **reject/accept oracle** only |
| **R1** | Custom kernel, sched_ext optional | SECURITY-IMPACT for kernel surfaces |
| **R2** | KASAN + syzkaller | Triage → claim only after minimized repro on R1 |

## Scripts (entry points)

```bash
# Fingerprint this machine (always first)
bash scripts/research/live-preflight.sh

# Smoke: preflight + verifier negative control + minimal load
bash scripts/research/run-research-gate.sh

# Verify a filed claim directory
bash scripts/research/bypass-claim-verify.sh research/claims/BP-000-template
```

Ledger: `scripts/oneclick/results/research/RESEARCH_LEDGER.md` (separate from `OUR_GOAL.md`).

## Relation to Elite product

- `docs/research/problems/U01.md`: verifier invention is **out of product scope**; this charter governs **personal / upstream** research hygiene only.
- SCX strict verifier (`scripts/verify-scx-1202-evidence.sh`) remains valid for **fix evidence**, not for bypass hunting.
