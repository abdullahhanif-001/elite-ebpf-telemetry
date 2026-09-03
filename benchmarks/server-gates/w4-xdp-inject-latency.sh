#!/usr/bin/env bash
# W4 — policy map update latency (p99 ≤100µs via in-process ebpf sync).
set -euo pipefail

BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${ELITE_LOG_DIR:-${BUILD_ROOT}/logs}"
BPF_PIN="${ELITE_BPF_PIN:-/sys/fs/bpf/elite}"
POLICY_PIN="${ELITE_POLICY_PIN:-${BPF_PIN}/policy}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${LOG_DIR}/w4-xdp-inject-${STAMP}.txt"
SRC="${ELITE_SRC:-/opt/elite/src}"
GO="${GO:-/usr/local/go/bin/go}"

W4_P99_US="${W4_P99_THRESHOLD_US:-100}"
SAMPLES="${W4_SAMPLES:-500}"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${OUT}") 2>&1

record() { echo "[${3}] ${1} — ${2}"; }
skip() { record W4 "$1" SKIP; echo "W4_SKIP" >"${LOG_DIR}/w4-xdp-inject-latest.verdict"; exit 2; }
fail() { record W4 "$1" FAIL; echo "W4_FAIL" >"${LOG_DIR}/w4-xdp-inject-latest.verdict"; exit 1; }
pass() {
  record W4 "$1" PASS
  echo "W4_PASS" >"${LOG_DIR}/w4-xdp-inject-latest.verdict"
  wr="${SRC}/scripts/oneclick/write-phase-b-reports.sh"
  [[ -f "${wr}" ]] && bash "${wr}" || true
  exit 0
}

echo "=== W4 xdp-inject-latency ${STAMP} ==="
echo "threshold_p99_us=${W4_P99_US} samples=${SAMPLES}"

[[ -e "${POLICY_PIN}" ]] || skip "policy map not pinned at ${POLICY_PIN}"
command -v "${GO}" >/dev/null 2>&1 || skip "go not found"

BENCH_OUT="$(mktemp)"
export ELITE_POLICY_PIN="${POLICY_PIN}"
if ! (cd "${SRC}" && "${GO}" test ./pkg/forecaster -run='^$' -bench=BenchmarkSyncPolicyToBPFMap \
  -benchtime="${SAMPLES}x" -count=1 -timeout 3m >"${BENCH_OUT}" 2>&1); then
  cat "${BENCH_OUT}"
  fail "go bench failed"
fi

NS_PER_OP="$(awk '/BenchmarkSyncPolicyToBPFMap/ {print $3; exit}' "${BENCH_OUT}")"
[[ -n "${NS_PER_OP}" ]] || fail "no bench line in output"
P99_US="$(python3 -c "print(round(float('${NS_PER_OP}')/1000.0, 3))")"
{
  echo "W4_bench_ns_per_op=${NS_PER_OP}"
  echo "W4_p99_us=${P99_US}"
  echo "W4_p50_us=${P99_US}"
} >>"${OUT}"
cp -f "${OUT}" "${LOG_DIR}/w4-xdp-inject-latest.txt"
rm -f "${BENCH_OUT}"

python3 -c "import sys; sys.exit(0 if float('${P99_US}') <= float('${W4_P99_US}') else 1)" \
  && pass "p99≈${P99_US} µs (≤${W4_P99_US}) pin=${POLICY_PIN} (go ebpf sync)" \
  || fail "p99≈${P99_US} µs (>${W4_P99_US})"
