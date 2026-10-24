#!/usr/bin/env bash
# run-load-oracle.sh — compile minimal BPF programs and check verifier oracle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROG_DIR="${ROOT}/research/verifier/programs"
OUT_DIR="${1:-${ROOT}/scripts/oneclick/results/research/verifier-oracle}"
mkdir -p "${OUT_DIR}"

HDR="${ROOT}/bpf/headers"
ARCH="${RESEARCH_BPF_ARCH:-x86}"
case "${ARCH}" in
  x86 | amd64) TARGET="-D__TARGET_ARCH_x86" ;;
  arm64 | aarch64) TARGET="-D__TARGET_ARCH_arm64" ;;
  *) echo "FAIL: unknown RESEARCH_BPF_ARCH=${ARCH}" >&2; exit 1 ;;
esac

if ! command -v clang >/dev/null 2>&1; then
  echo "VERIFIER_ORACLE_SKIP reason=no_clang" | tee "${OUT_DIR}/verdict.txt"
  exit 0
fi

compile_one() {
  local src="$1" obj="$2"
  clang -g -O2 -target bpf -c "${src}" -o "${obj}" \
    -I "${HDR}" ${TARGET} -Wno-address-of-packed-member 2>"${obj}.clang.log"
}

FAIL=0
emit_verdict() {
  echo "$1" | tee "${OUT_DIR}/verdict.txt"
}

cd "${OUT_DIR}"
compile_one "${PROG_DIR}/minimal_pass.bpf.c" "minimal_pass.bpf.o"
compile_one "${PROG_DIR}/negative_reject.bpf.c" "negative_reject.bpf.o"

# Userspace load via cilium/ebpf (exercises kernel verifier on load)
loadprobe_cmd() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    go run "${ROOT}/research/verifier/cmd/loadprobe/main.go" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n go run "${ROOT}/research/verifier/cmd/loadprobe/main.go" "$@"
  else
    go run "${ROOT}/research/verifier/cmd/loadprobe/main.go" "$@"
  fi
}

run_loadprobe() {
  local obj="$1" expect_ok="$2" label="$3"
  local log="${OUT_DIR}/${label}.loadprobe.json"
  set +e
  loadprobe_cmd "${obj}" > "${log}" 2>&1
  local rc=$?
  set -e
  if [[ "${expect_ok}" == "yes" ]]; then
    if [[ "${rc}" -eq 0 ]] && grep -q LOADPROBE_OK "${log}"; then
      echo "OK ${label} load accepted (expected)"
    else
      echo "FAIL ${label} expected load OK rc=${rc}" >&2
      cat "${log}" >&2
      FAIL=$((FAIL + 1))
    fi
  else
    if [[ "${rc}" -ne 0 ]] && grep -q LOADPROBE_FAIL "${log}"; then
      echo "OK ${label} load rejected (expected)"
    else
      echo "FAIL ${label} expected verifier reject rc=${rc}" >&2
      cat "${log}" >&2
      FAIL=$((FAIL + 1))
    fi
  fi
}

run_loadprobe "${OUT_DIR}/minimal_pass.bpf.o" yes "minimal_pass"
run_loadprobe "${OUT_DIR}/negative_reject.bpf.o" no "negative_reject"

# Truncated ELF — must fail before a bypass claim is trusted
head -c 64 "${OUT_DIR}/minimal_pass.bpf.o" > "${OUT_DIR}/negative_truncated.bpf.o"
run_loadprobe "${OUT_DIR}/negative_truncated.bpf.o" no "negative_truncated"

if [[ "${FAIL}" -gt 0 ]]; then
  emit_verdict "VERIFIER_ORACLE_FAIL fail=${FAIL}"
  exit 1
fi

emit_verdict "VERIFIER_ORACLE_PASS fail=0"
exit 0
