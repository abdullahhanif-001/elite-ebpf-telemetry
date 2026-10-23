# Verifier smoke oracle (R0+)

Exercises the **kernel verifier** via `cilium/ebpf` load — not a bypass finder by itself.
It proves the lab can distinguish **accept** vs **reject** on the **live** kernel.

| Program | Expected |
|---------|----------|
| `programs/minimal_pass.bpf.c` | Load OK |
| `programs/negative_reject.bpf.c` | Verifier reject (invalid helper for socket prog) |

```bash
bash research/verifier/run-load-oracle.sh
# or full smoke:
bash scripts/research/run-research-gate.sh
```

Requires: `clang`, `go`, and permission to load BPF (often `sudo`). If load fails
with `operation not permitted`, fix capabilities — do not mark offline PASS.

`research/verifier/cmd/loadprobe` prints JSON + `LOADPROBE_OK` / `LOADPROBE_FAIL`.
