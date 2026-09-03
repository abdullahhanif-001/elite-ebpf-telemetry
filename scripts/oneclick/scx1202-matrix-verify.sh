#!/usr/bin/env bash
# Back-compat wrapper — SCX1202 gate matrix verifier on VPS.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/benchmarks/ebpf-gates/scx1202-matrix-verify.sh" "$@"
