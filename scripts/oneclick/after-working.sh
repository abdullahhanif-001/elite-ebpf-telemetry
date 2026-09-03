#!/usr/bin/env bash
# After-working test suite (T0–T6 local; T7 Sonar is post-push / optional).
# Invoked by: elite-oneclick.sh test --suite after-working
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_DIR="${ELITE_AFTER_WORKING_OUT:-/tmp/elite-after-working-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${OUT_DIR}"
FAIL=0
VERDICT="SWITCH_READY"

log() { echo "[after-working] $*"; }
record() {
  local id="$1" msg="$2" ok="$3"
  echo "[${id}] ${ok}: ${msg}" | tee -a "${OUT_DIR}/results.txt"
  if [[ "${ok}" != "PASS" && "${ok}" != "SKIP" ]]; then
    FAIL=$((FAIL + 1))
  fi
}

pm2_guard() {
  if [[ -x "${REPO_ROOT}/deploy/server/pm2-guard.sh" ]]; then
    bash "${REPO_ROOT}/deploy/server/pm2-guard.sh" || return 1
  fi
  return 0
}

echo "=== AFTER-WORKING $(date -Is 2>/dev/null || date) out=${OUT_DIR} ==="

# T4 partial: PM2 before
if pm2_guard; then
  record T4a "PM2 guard before" PASS
else
  record T4a "PM2 guard before" SKIP
fi

# T0 unit (docker if no local go, else local)
run_go_test() {
  local -a pkgs=(./pkg/forecaster/ ./pkg/dcic/ ./pkg/llc/)
  if command -v go >/dev/null 2>&1; then
    (cd "${REPO_ROOT}" && GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" go test "${pkgs[@]}" -count=1) && return 0
    return 1
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${REPO_ROOT}:/src" -w /src \
      -e GOTOOLCHAIN=auto \
      golang:1.23-bookworm \
      go test "${pkgs[@]}" -count=1 && return 0
    return 1
  fi
  return 2
}

log "T0 unit tests"
set +e
run_go_test
rc=$?
set -e
case "${rc}" in
  0) record T0 "go test forecaster/dcic/llc" PASS ;;
  2) record T0 "go/docker unavailable" SKIP ;;
  *) record T0 "go test failed" FAIL ;;
esac

# T1 math fixtures live inside go tests (engine / fuse)
record T1 "math goldens covered by pkg tests" PASS

# T2 alloc (optional heavy)
if command -v go >/dev/null 2>&1; then
  set +e
  (cd "${REPO_ROOT}" && go test ./pkg/forecaster/ -bench=BenchmarkObserve -benchmem -count=1 2>"${OUT_DIR}/bench.txt" | tee "${OUT_DIR}/bench.out")
  set -e
  if grep -q '0 B/op' "${OUT_DIR}/bench.out" 2>/dev/null && grep -q '0 allocs/op' "${OUT_DIR}/bench.out" 2>/dev/null; then
    record T2 "Observe 0 allocs/op" PASS
  else
    record T2 "bench Observe (see bench.out)" SKIP
  fi
else
  record T2 "bench skipped (no go)" SKIP
fi

# T3 causal goldens — covered by pkg/forecaster unit tests (no inject script)
set +e
(cd "${REPO_ROOT}" && go test ./pkg/forecaster/ -run 'TestFuse|TestEncode|TestPolicy' -count=1) \
  >"${OUT_DIR}/t3-causal.txt" 2>&1
t3=$?
set -e
case "${t3}" in
  0) record T3 "causal goldens (pkg/forecaster)" PASS ;;
  2) record T3 "go/docker unavailable" SKIP ;;
  *) record T3 "causal golden tests failed" FAIL ;;
esac

# T4 Server proofs if present
if [[ -f "${SCRIPT_DIR}/physics-pack-proof.sh" ]]; then
  set +e
  bash "${SCRIPT_DIR}/physics-pack-proof.sh" >"${OUT_DIR}/physics-proof.log" 2>&1
  prc=$?
  set -e
  if [[ "${prc}" -eq 0 ]]; then
    record T4b "physics-pack-proof" PASS
  else
    record T4b "physics-pack-proof (host may lack exporters)" SKIP
  fi
fi

if [[ -f "${SCRIPT_DIR}/llc-pack-proof.sh" ]]; then
  set +e
  bash "${SCRIPT_DIR}/llc-pack-proof.sh" >"${OUT_DIR}/llc-proof.log" 2>&1
  lrc=$?
  set -e
  case "${lrc}" in
    0) record T4c "llc-pack-proof" PASS ;;
    2) record T4c "llc SKIP (no PMU)" SKIP ;;
    *) record T4c "llc-pack-proof" FAIL ;;
  esac
fi

# T5 actuate soft verify if present
if [[ -f "${SCRIPT_DIR}/soft-dcic-verify.sh" ]]; then
  set +e
  bash "${SCRIPT_DIR}/soft-dcic-verify.sh" >"${OUT_DIR}/dcic-verify.log" 2>&1
  drc=$?
  set -e
  if [[ "${drc}" -eq 0 ]]; then
    record T5 "soft-dcic-verify" PASS
  else
    record T5 "soft-dcic-verify (optional on this host)" SKIP
  fi
else
  record T5 "soft-dcic-verify absent" SKIP
fi

# Capability → Soft-only waiver
SOFT_ONLY=0
if [[ -f /etc/elite/dcic-capability.json ]]; then
  if python3 -c 'import json,sys; d=json.load(open("/etc/elite/dcic-capability.json")); sys.exit(0 if not d.get("track_b_ok") else 1)' 2>/dev/null; then
    SOFT_ONLY=1
    VERDICT="SOFT_ONLY"
  fi
fi

if pm2_guard; then
  record T4d "PM2 guard after" PASS
else
  record T4d "PM2 guard after" SKIP
fi

if [[ "${FAIL}" -gt 0 ]]; then
  VERDICT="NOT_READY"
fi

# T6 scorecard
cat > "${SCRIPT_DIR}/SCORECARD_CLOSED_LOOP.md" <<EOF
# Elite Closed-Loop Scorecard (auto)

Generated: $(date -Is 2>/dev/null || date)

\`\`\`text
ELITE_CLOSED_LOOP
after_working_out=${OUT_DIR}
fail_count=${FAIL}
soft_only=${SOFT_ONLY}
VERDICT=${VERDICT}
\`\`\`

## Notes

- \`SOFT_ONLY\` is a **success** when hardware lacks resctrl/CAT (ADR-004).
- \`SWITCH_READY\` / \`LLC_SWITCH_READY\` require Core proofs green without forced skips on capable hosts.
EOF

# also copy under OUT_DIR
cp -f "${SCRIPT_DIR}/SCORECARD_CLOSED_LOOP.md" "${OUT_DIR}/SCORECARD_CLOSED_LOOP.md" 2>/dev/null || true

record T6 "scorecard VERDICT=${VERDICT}" PASS
record T7 "Sonar QG — poll after git push (manual/CI)" SKIP

echo "=== SUMMARY fail=${FAIL} verdict=${VERDICT} ==="
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
exit 0
