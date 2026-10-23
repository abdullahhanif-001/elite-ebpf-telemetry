# Userspace loader fuzz (R0)

**Impact class:** `USERSPACE` or `HYPOTHESIS` only until reproduced on R1 with kernel load.

Planned corpus sources:

- `pkg/exporter/testbtf/bpf_bpfel.o`
- Objects built from `contrib/sched-ext/selftests/*.bpf.c`

Runner (stub — extend with AFL++/custom mutator):

```bash
bash research/fuzz/run-libbpf-smoke.sh
```

Do **not** set `ELITE_OFFLINE=1`. File kernel bypass claims only via
[research/BYPASS_CLAIM_CHARTER.md](../BYPASS_CLAIM_CHARTER.md).
