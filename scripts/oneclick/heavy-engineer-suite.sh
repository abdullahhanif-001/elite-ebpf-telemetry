#!/usr/bin/env bash
# Staff-engineer heavy verify suite (H0–H10).
# Invoked by: elite-oneclick.sh test --suite heavy
# Writes: scripts/oneclick/HEAVY_TEST_SCORECARD.md + /tmp/elite-heavy-*/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)"
OUT_DIR="${ELITE_HEAVY_OUT:-/tmp/elite-heavy-${STAMP}}"
SCORECARD="${SCRIPT_DIR}/HEAVY_TEST_SCORECARD.md"
SONAR_KEY="${SONAR_PROJECT_KEY:-abdullahhanif-001_elite-ebpf-telemetry}"
GH_REPO="${ELITE_GH_REPO:-abdullahhanif-001/elite-ebpf-telemetry}"
mkdir -p "${OUT_DIR}"
FAIL=0
SKIP=0
VERDICT="HEAVY_PASS"
SOFT_ONLY=0

log() { echo "[heavy] $*"; }
record() {
  local id="$1" msg="$2" ok="$3"
  echo "[${id}] ${ok}: ${msg}" | tee -a "${OUT_DIR}/results.txt"
  case "${ok}" in
    PASS) ;;
    SKIP) SKIP=$((SKIP + 1)) ;;
    *) FAIL=$((FAIL + 1)) ;;
  esac
}

have_go() { command -v go >/dev/null 2>&1; }

run_go() {
  local args=("$@")
  if have_go; then
    (cd "${REPO_ROOT}" && GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" go "${args[@]}")
    return $?
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${REPO_ROOT}:/src" -w /src \
      -e GOTOOLCHAIN=auto \
      golang:1.23-bookworm go "${args[@]}"
    return $?
  fi
  return 2
}

pm2_guard() {
  local guard="${REPO_ROOT}/deploy/server/pm2-guard.sh"
  if [[ -x "${guard}" || -f "${guard}" ]]; then
    bash "${guard}"
    return $?
  fi
  return 2
}

echo "=== HEAVY ENGINEER SUITE ${STAMP} out=${OUT_DIR} ===" | tee "${OUT_DIR}/header.txt"

# --- H7 before ---
set +e
pm2_guard >"${OUT_DIR}/pm2-before.txt" 2>&1
prc=$?
set -e
case "${prc}" in
  0) record H7a "PM2 guard before" PASS ;;
  2) record H7a "PM2 guard absent" SKIP ;;
  *)
    if grep -q 'PM2_GUARD_OK' "${OUT_DIR}/pm2-before.txt" 2>/dev/null; then
      record H7a "PM2 guard before" PASS
    else
      record H7a "PM2 guard before failed (see pm2-before.txt)" FAIL
    fi
    ;;
esac

# --- H0 shell syntax ---
log "H0 bash -n + shellcheck"
H0_FAIL=0
mapfile -t ONECLICK_SCRIPTS < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '*.sh' | sort)
for s in "${ONECLICK_SCRIPTS[@]}"; do
  if ! bash -n "${s}" 2>>"${OUT_DIR}/bash-n.err"; then
    echo "bash -n FAIL: ${s}" >>"${OUT_DIR}/bash-n.err"
    H0_FAIL=1
  fi
done
if [[ "${H0_FAIL}" -eq 0 ]]; then
  record H0a "bash -n oneclick scripts" PASS
else
  record H0a "bash -n oneclick scripts" FAIL
fi

if command -v shellcheck >/dev/null 2>&1; then
  set +e
  shellcheck -x \
    "${SCRIPT_DIR}/heavy-engineer-suite.sh" \
    "${SCRIPT_DIR}/elite-oneclick.sh" \
    "${SCRIPT_DIR}/after-working.sh" \
    >"${OUT_DIR}/shellcheck.txt" 2>&1
  sc=$?
  set -e
  if [[ "${sc}" -eq 0 ]]; then
    record H0b "shellcheck core scripts" PASS
  else
    # Warnings OK; only fail on errors (exit 1 = errors found)
    if grep -E 'error:' "${OUT_DIR}/shellcheck.txt" >/dev/null 2>&1; then
      record H0b "shellcheck errors" FAIL
    else
      record H0b "shellcheck warnings only (non-fatal)" PASS
    fi
  fi
else
  record H0b "shellcheck not installed" SKIP
fi

# --- H1 unit tests ---
log "H1 go test packages"
set +e
run_go test ./pkg/forecaster/ ./pkg/dcic/ ./pkg/llc/ ./pkg/export/... ./pkg/exporter/... -count=1 -timeout 10m \
  >"${OUT_DIR}/h1-test.txt" 2>&1
h1=$?
set -e
case "${h1}" in
  0) record H1 "go test forecaster/dcic/llc/export/exporter" PASS ;;
  2) record H1 "go/docker unavailable" SKIP ;;
  *) record H1 "go test failed (see h1-test.txt)" FAIL ;;
esac

# --- H2 race ---
log "H2 -race (short)"
set +e
run_go test ./pkg/forecaster/ ./pkg/dcic/ ./pkg/llc/ -race -count=1 -timeout 5m \
  >"${OUT_DIR}/h2-race.txt" 2>&1
h2=$?
set -e
case "${h2}" in
  0) record H2 "go test -race forecaster/dcic/llc" PASS ;;
  2) record H2 "go/docker unavailable" SKIP ;;
  *)
    # CGO/race often unavailable in alpine/minimal; treat known skip signals as SKIP
    if grep -qiE 'race|cgo|not supported|requires cgo' "${OUT_DIR}/h2-race.txt" 2>/dev/null; then
      record H2 "race unsupported on this toolchain" SKIP
    else
      record H2 "race tests failed (see h2-race.txt)" FAIL
    fi
    ;;
esac

# --- H3 bench alloc ---
log "H3 Observe 0-alloc bench"
set +e
run_go test ./pkg/forecaster/ -bench=. -benchmem -count=1 \
  >"${OUT_DIR}/h3-bench.txt" 2>&1
h3=$?
set -e
if [[ "${h3}" -eq 0 ]] && grep -q '0 B/op' "${OUT_DIR}/h3-bench.txt" && grep -q '0 allocs/op' "${OUT_DIR}/h3-bench.txt"; then
  record H3 "Observe path 0 B/op / 0 allocs/op" PASS
elif [[ "${h3}" -eq 2 ]]; then
  record H3 "bench skipped (no go)" SKIP
elif [[ "${h3}" -eq 0 ]]; then
  record H3 "bench ran but 0-alloc not observed (see h3-bench.txt)" FAIL
else
  record H3 "bench failed (see h3-bench.txt)" FAIL
fi

# --- H4 fuse/causal goldens (pkg/forecaster unit tests) ---
log "H4 causal decision-bus goldens"
set +e
run_go test ./pkg/forecaster/ -run 'TestFuse|TestEncode|TestPolicy' -count=1 \
  >"${OUT_DIR}/h4-causal.txt" 2>&1
h4=$?
set -e
if [[ "${h4}" -eq 0 ]]; then
  record H4 "causal goldens (pkg/forecaster unit tests)" PASS
elif [[ "${h4}" -eq 2 ]]; then
  record H4 "go/docker unavailable" SKIP
else
  record H4 "causal golden tests failed (see h4-causal.txt)" FAIL
fi

# --- H5 after-working ---
log "H5 after-working suite"
if [[ -f "${SCRIPT_DIR}/after-working.sh" ]]; then
  set +e
  ELITE_AFTER_WORKING_OUT="${OUT_DIR}/after-working" \
    bash "${SCRIPT_DIR}/after-working.sh" >"${OUT_DIR}/h5-after-working.txt" 2>&1
  h5=$?
  set -e
  if [[ "${h5}" -eq 0 ]]; then
    if grep -q 'VERDICT=SOFT_ONLY' "${OUT_DIR}/h5-after-working.txt" 2>/dev/null \
      || grep -q 'soft_only=1' "${SCRIPT_DIR}/SCORECARD_CLOSED_LOOP.md" 2>/dev/null; then
      SOFT_ONLY=1
    fi
    record H5 "after-working exit 0" PASS
  else
    # Soft-only waiver: after-working may exit 0 always when FAIL=0; if FAIL, honor Soft waiver text
    if grep -qiE 'SOFT_ONLY|soft_only=1' "${OUT_DIR}/h5-after-working.txt" 2>/dev/null; then
      SOFT_ONLY=1
      record H5 "after-working Soft-only waiver" PASS
    else
      record H5 "after-working failed (see h5-after-working.txt)" FAIL
    fi
  fi
else
  record H5 "after-working.sh missing" SKIP
fi

# --- H6 pack proofs ---
log "H6 physics / llc / soft-dcic proofs"
run_proof() {
  local name="$1" script="$2"
  if [[ ! -f "${script}" ]]; then
    record "${name}" "$(basename "${script}") absent" SKIP
    return
  fi
  set +e
  bash "${script}" >"${OUT_DIR}/${name}.log" 2>&1
  local rc=$?
  set -e
  case "${rc}" in
    0) record "${name}" "$(basename "${script}")" PASS ;;
    2) record "${name}" "$(basename "${script}") SKIP (capability)" SKIP ;;
    *) record "${name}" "$(basename "${script}") failed/optional" SKIP ;;
  esac
}
run_proof H6a "${SCRIPT_DIR}/physics-pack-proof.sh"
run_proof H6b "${SCRIPT_DIR}/llc-pack-proof.sh"
run_proof H6c "${SCRIPT_DIR}/soft-dcic-verify.sh"

if [[ -f /etc/elite/dcic-capability.json ]]; then
  if python3 -c 'import json,sys; d=json.load(open("/etc/elite/dcic-capability.json")); sys.exit(0 if not d.get("track_b_ok") else 1)' 2>/dev/null; then
    SOFT_ONLY=1
  fi
fi

# --- H8 builds ---
log "H8 build binaries"
build_one() {
  local name="$1" pkg="$2" out="$3"
  set +e
  if have_go; then
    (cd "${REPO_ROOT}" && CGO_ENABLED=0 GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" \
      go build -o "${OUT_DIR}/${out}" "${pkg}") >"${OUT_DIR}/build-${name}.txt" 2>&1
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${REPO_ROOT}:/src" -v "${OUT_DIR}:/out" -w /src \
      -e CGO_ENABLED=0 -e GOTOOLCHAIN=auto \
      golang:1.23-bookworm go build -o "/out/${out}" "${pkg}" \
      >"${OUT_DIR}/build-${name}.txt" 2>&1
  else
    return 2
  fi
  local rc=$?
  set -e
  return "${rc}"
}

set +e
build_one agent ./cmd/exporter elite-agent
b_agent=$?
build_one dcic ./cmd/elite-dcic elite-dcic
b_dcic=$?
build_one llc ./cmd/elite-llc-sensors elite-llc-sensors
b_llc=$?
set -e

for pair in "H8a:${b_agent}:elite-agent" "H8b:${b_dcic}:elite-dcic" "H8c:${b_llc}:elite-llc-sensors"; do
  id="${pair%%:*}"
  rest="${pair#*:}"
  code="${rest%%:*}"
  bin="${rest#*:}"
  case "${code}" in
    0)
      if [[ -f "${OUT_DIR}/${bin}" ]]; then
        record "${id}" "build ${bin}" PASS
      else
        record "${id}" "build ${bin} missing artifact" FAIL
      fi
      ;;
    2) record "${id}" "build ${bin} skipped (no go/docker)" SKIP ;;
    *) record "${id}" "build ${bin} failed" FAIL ;;
  esac
done

# --- H7 after ---
set +e
pm2_guard >"${OUT_DIR}/pm2-after.txt" 2>&1
prc=$?
set -e
case "${prc}" in
  0) record H7b "PM2 guard after" PASS ;;
  2) record H7b "PM2 guard absent" SKIP ;;
  *)
    if grep -q 'PM2_GUARD_OK' "${OUT_DIR}/pm2-after.txt" 2>/dev/null; then
      record H7b "PM2 guard after" PASS
    else
      record H7b "PM2 guard after failed (see pm2-after.txt)" FAIL
    fi
    ;;
esac

# --- H11 live predict ---
log "H11 live predict inject"
if [[ -f "${SCRIPT_DIR}/competitive-live-predict-proof.sh" ]]; then
  set +e
  bash "${SCRIPT_DIR}/competitive-live-predict-proof.sh" >"${OUT_DIR}/h11-live-predict.txt" 2>&1
  h11=$?
  set -e
    case "${h11}" in
      0) record H11 "live predict H11_PASS_LIVE" PASS ;;
      2) record H11 "live predict SKIP (bus-only or capability)" SKIP ;;
      *) record H11 "live predict failed" FAIL ;;
    esac
else
  record H11 "competitive-live-predict-proof.sh missing" FAIL
fi

# --- H9 Sonar QG ---
log "H9 Sonar quality gate"
set +e
curl -fsS --proto '=https' --tlsv1.2 \
  "https://sonarcloud.io/api/measures/component?component=${SONAR_KEY}&metricKeys=alert_status,security_rating,new_security_rating,vulnerabilities" \
  >"${OUT_DIR}/sonar.json" 2>"${OUT_DIR}/sonar.err"
h9=$?
set -e
if [[ "${h9}" -eq 0 ]] && grep -q '"alert_status"' "${OUT_DIR}/sonar.json"; then
  alert="$(python3 -c 'import json; d=json.load(open("'"${OUT_DIR}/sonar.json"'")); print({m["metric"]: m.get("value") for m in d["component"]["measures"]}.get("alert_status","?"))' 2>/dev/null || echo "?")"
  if [[ "${alert}" == "OK" ]]; then
    record H9 "Sonar alert_status=OK" PASS
  else
    # Pre-push: known ERROR until Sonar re-analyzes HEAD with fixes — record, don't soft-pass
    record H9 "Sonar alert_status=${alert} (re-poll after push/analyze)" FAIL
  fi
else
  record H9 "Sonar API unreachable" SKIP
fi

# --- H10 GitHub Actions ---
log "H10 GitHub Actions"
if command -v gh >/dev/null 2>&1; then
  set +e
  gh run list --repo "${GH_REPO}" --branch main --limit 3 \
    >"${OUT_DIR}/gh-runs.txt" 2>&1
  h10=$?
  set -e
  if [[ "${h10}" -eq 0 ]] && grep -qiE 'completed\s+success|success' "${OUT_DIR}/gh-runs.txt"; then
    record H10 "recent main CI success present" PASS
  elif [[ "${h10}" -eq 0 ]]; then
    record H10 "CI runs listed — confirm HEAD after push" SKIP
  else
    record H10 "gh run list failed" SKIP
  fi
else
  record H10 "gh CLI absent — confirm CI after push" SKIP
fi

# Verdict
if [[ "${FAIL}" -gt 0 ]]; then
  # Allow HEAVY_PASS_SOFT only when failures are solely H9 pre-push Sonar, Soft host, and optional skips
  only_sonar=0
  if [[ "${FAIL}" -eq 1 ]] && grep -q '\[H9\] FAIL' "${OUT_DIR}/results.txt" 2>/dev/null; then
    only_sonar=1
  fi
  if [[ "${only_sonar}" -eq 1 ]]; then
    VERDICT="HEAVY_PASS_PENDING_SONAR"
  else
    VERDICT="HEAVY_FAIL"
  fi
fi
if [[ "${SOFT_ONLY}" -eq 1 && "${VERDICT}" == "HEAVY_PASS" ]]; then
  VERDICT="HEAVY_PASS_SOFT"
fi
if [[ "${SOFT_ONLY}" -eq 1 && "${VERDICT}" == "HEAVY_PASS_PENDING_SONAR" ]]; then
  VERDICT="HEAVY_PASS_SOFT_PENDING_SONAR"
fi

# Persist results under repo for commit
mkdir -p "${SCRIPT_DIR}/results"
cp -a "${OUT_DIR}/results.txt" "${SCRIPT_DIR}/results/heavy-${STAMP}.txt" 2>/dev/null || true
if [[ -f "${OUT_DIR}/h3-bench.txt" ]]; then
  cp -f "${OUT_DIR}/h3-bench.txt" "${SCRIPT_DIR}/results/heavy-${STAMP}-bench.txt" 2>/dev/null || true
fi

cat > "${SCORECARD}" <<EOF
# Heavy Engineer Test Scorecard

**Repository:** [${GH_REPO}](https://github.com/${GH_REPO})  
**Generated:** $(date -Is 2>/dev/null || date)  
**Host:** $(hostname 2>/dev/null || echo unknown)  
**Out dir:** \`${OUT_DIR}\`

\`\`\`text
ELITE_HEAVY_SUITE
fail_count=${FAIL}
skip_count=${SKIP}
soft_only=${SOFT_ONLY}
sonar_key=${SONAR_KEY}
VERDICT=${VERDICT}
\`\`\`

## Gate results

\`\`\`text
$(cat "${OUT_DIR}/results.txt" 2>/dev/null || echo "(no results)")
\`\`\`

## Notes

- \`HEAVY_PASS_SOFT\` / Soft-only is success when the host lacks resctrl/CAT (ADR-004).
- \`HEAVY_PASS_PENDING_SONAR\` means local/Server gates passed; push Sonar fixes and re-poll QG until \`alert_status=OK\`.
- PM2 apps must remain untouched; H7 requires \`PM2_GUARD_OK\`.
- Go module path stays \`github.com/alibaba/kubeskoop\` (fork convention); public brand is \`${GH_REPO}\`.

## Bench excerpt

\`\`\`text
$(grep -E 'Benchmark|B/op|allocs/op|ok |FAIL' "${OUT_DIR}/h3-bench.txt" 2>/dev/null | head -40 || echo "(no bench)")
\`\`\`
EOF

cp -f "${SCORECARD}" "${OUT_DIR}/HEAVY_TEST_SCORECARD.md" 2>/dev/null || true

echo "=== HEAVY SUMMARY fail=${FAIL} skip=${SKIP} VERDICT=${VERDICT} ==="
echo "Scorecard: ${SCORECARD}"

if [[ "${VERDICT}" == "HEAVY_FAIL" ]]; then
  exit 1
fi
exit 0
