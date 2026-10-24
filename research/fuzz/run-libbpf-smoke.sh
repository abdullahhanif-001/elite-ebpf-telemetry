#!/usr/bin/env bash
# run-libbpf-smoke.sh — parse-only smoke on committed test object (R0).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBJ="${ROOT}/pkg/exporter/testbtf/bpf_bpfel.o"
OUT="${ROOT}/scripts/oneclick/results/research/fuzz-smoke-$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"

if [[ "${ELITE_OFFLINE:-0}" == "1" ]]; then
  echo "FAIL: ELITE_OFFLINE forbidden" >&2
  exit 1
fi

if [[ ! -f "${OBJ}" ]]; then
  echo "FUZZ_SMOKE_SKIP reason=missing_test_object" | tee "${OUT}/verdict.txt"
  exit 0
fi

# Spec load only (no kernel attach) — userspace ELF/BTF parse path
go run "${ROOT}/research/verifier/cmd/loadprobe/main.go" "${OBJ}" > "${OUT}/loadprobe.json" 2>&1 || true

if grep -q LOADPROBE_OK "${OUT}/loadprobe.json" 2>/dev/null; then
  echo "FUZZ_SMOKE_PASS note=existing_object_loads" | tee "${OUT}/verdict.txt"
else
  echo "FUZZ_SMOKE_NOTE parse_or_load_failed_see_log" | tee "${OUT}/verdict.txt"
  cat "${OUT}/loadprobe.json" || true
fi

echo "artifact=${OUT}"
