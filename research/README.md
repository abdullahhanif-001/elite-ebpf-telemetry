# Kernel / eBPF bypass research lab (local VM)

VPS-independent harnesses and **fail-closed** claim rules. Read
[research/BYPASS_CLAIM_CHARTER.md](./BYPASS_CLAIM_CHARTER.md) first.

| Path | Purpose |
|------|---------|
| [scripts/research/](../scripts/research/) | Live preflight, gates, claim verifier |
| [research/verifier/](./verifier/) | Minimal BPF load oracle (verifier smoke) |
| [research/fuzz/](./fuzz/) | Userspace loader fuzz (R0); kernel claims need R1 |
| [research/claims/](./claims/) | Filed claims (`BP-*`); template is non-passing example |

Quick start:

```bash
bash scripts/research/run-research-gate.sh
```
