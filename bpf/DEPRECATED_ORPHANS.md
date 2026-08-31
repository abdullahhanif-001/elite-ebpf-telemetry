# Deprecated Orphan BPF Programs

These `bpf/*.c` sources have **no bpf2go loader** in `pkg/exporter/probe/`.
They are retained for reference only until wired or removed.

| File | Status | Notes |
|------|--------|-------|
| `tasklatency.c` | DEPRECATED | `tracetasklatency` Go package is stub-only |
| `nflatancy.c` | DEPRECATED | No loader |
| `flowcount.c` | DEPRECATED | No loader |
| `netns.c` | DEPRECATED | No loader |
| `rxkernel.c` | DEPRECATED | No loader |
| `txkernel.c` | DEPRECATED | No loader |

Inventory gate `ebpf-future-holes.sh` FH3 expects this file when orphans exist.
