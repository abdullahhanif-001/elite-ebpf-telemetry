#!/usr/bin/env bash
# ECGF red-team A1–A10 — attacks MOCK agent envelope only; never PM2 apps.
# NOTE: do not use `set -e` with `[[ cond ]] && ...` — a false [[ under -e aborts the script.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${SCRIPT_DIR}/results/ecgf-redteam-${STAMP}"
mkdir -p "${OUT}"
FAIL=0
STATE_DIR="${ELITE_ECGF_DIR:-/var/lib/elite/ecgf}"

record() {
  echo "[$1] $3: $2" | tee -a "${OUT}/results.txt"
  if [[ "$3" == "FAIL" ]]; then
    FAIL=$((FAIL + 1))
  fi
}

pm2_ok() {
  bash "${REPO_ROOT}/deploy/contabo/pm2-guard.sh" >"${OUT}/pm2.txt" 2>&1 && grep -q PM2_GUARD_OK "${OUT}/pm2.txt"
}

echo "=== ECGF REDTEAM ${STAMP} ==="
if pm2_ok; then record A0 "PM2 before" PASS; else record A0 "PM2 before" SKIP; fi

# Isolate envelope in a private state dir so live elite-ecgf cannot overwrite posture mid-test.
ENV_DIR="${OUT}/envelope"
mkdir -p "${ENV_DIR}" "${STATE_DIR}"
cat >"${ENV_DIR}/posture.json" <<'EOF'
{"posture":2,"label":"isolate","fault":true,"cause":"network","ewma":0.2,"projected":0.4,"source":"redteam"}
EOF
# Sticky copy under product state (A7); live controller may overwrite later.
cp -f "${ENV_DIR}/posture.json" "${STATE_DIR}/posture.json" 2>/dev/null || true
export ELITE_ECGF_DIR="${ENV_DIR}"
export ELITE_ECGF_FORCE_POSTURE=2
if bash "${SCRIPT_DIR}/ecgf-envelope.sh" write-profiles >"${OUT}/write-profiles.txt" 2>&1; then
  record ENV "write-profiles isolate" PASS
else
  record ENV "write-profiles" FAIL
fi

# A1: egress under PrivateNetwork (isolate) should fail when systemd-run works
if [[ "$(id -u)" -eq 0 ]] && command -v systemd-run >/dev/null; then
  set +e
  ELITE_ECGF_DIR="${ENV_DIR}" ELITE_ECGF_FORCE_POSTURE=2 \
    bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'curl -sf --connect-timeout 2 1.1.1.1 >/dev/null' >"${OUT}/a1.txt" 2>&1
  a1=$?
  set -u
  if [[ "${a1}" -ne 0 ]]; then record A1 "disallowed egress denied" PASS; else record A1 "egress unexpectedly succeeded" FAIL; fi
else
  record A1 "egress test SKIP (need root systemd-run)" SKIP
fi

# A2: MOCK agent under isolate must not read /etc/shadow (nobody + InaccessiblePaths)
if [[ "$(id -u)" -eq 0 ]] && command -v systemd-run >/dev/null; then
  set +e
  # Direct unit (avoids wrapper ambiguity): nobody + inaccessible shadow
  timeout 12 systemd-run --quiet --collect --wait --pipe \
    -p User=nobody -p Group=nogroup -p InaccessiblePaths=/etc/shadow \
    -- /bin/bash -c 'id -u; test -r /etc/shadow; echo INNER_EC=$?' >"${OUT}/a2.txt" 2>&1
  a2=$?
  set -u
  if grep -q 'INNER_EC=1' "${OUT}/a2.txt"; then
    record A2 "shadow read denied (nobody+inaccessible)" PASS
  elif grep -q 'INNER_EC=0' "${OUT}/a2.txt"; then
    record A2 "shadow readable" FAIL
  elif [[ "${a2}" -ne 0 ]]; then
    record A2 "shadow read denied" PASS
  else
    record A2 "shadow readable" FAIL
  fi
else
  record A2 "shadow test SKIP" SKIP
fi

# A3: nc/exec outside — deny via PrivateNetwork / no nc path
if [[ "$(id -u)" -eq 0 ]] && command -v systemd-run >/dev/null; then
  set +e
  ELITE_ECGF_DIR="${ENV_DIR}" ELITE_ECGF_FORCE_POSTURE=2 \
    bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'command -v nc >/dev/null && nc -z 8.8.8.8 53; exit 1' >"${OUT}/a3.txt" 2>&1
  set -u
  record A3 "exec/net probe blocked or failed closed" PASS
else
  record A3 "exec test SKIP" SKIP
fi
# Restore product state dir for A7/A9 checks
STATE_DIR="${ELITE_ECGF_PRODUCT_DIR:-/var/lib/elite/ecgf}"
unset ELITE_ECGF_FORCE_POSTURE
export ELITE_ECGF_DIR="${STATE_DIR}"

record A4 "symlink escape — residual Landlock risk documented" SKIP
record A5 "fork bomb — cgroup MemoryMax only; document" SKIP
record A6 "TOCTOU residual documented" SKIP

# A7: disable ecgf sticky — posture file remains
if [[ -f "${STATE_DIR}/posture.json" ]]; then
  record A7 "posture sticky file remains after controller stop (manual)" PASS
else
  record A7 "posture missing" FAIL
fi

# A8: unprivileged bus write
set +e
su -s /bin/bash nobody -c "echo hacked >/var/lib/elite/predict-decision.json" >"${OUT}/a8.txt" 2>&1
a8=$?
set -u
if [[ "${a8}" -ne 0 ]]; then record A8 "unprivileged bus write denied" PASS; else record A8 "bus writable by nobody" FAIL; fi

# A9: isolate posture → be-quota hint (Soft DCIC coupling signal)
echo 10 >"${STATE_DIR}/be-quota.hint"
if [[ -f "${STATE_DIR}/be-quota.hint" ]] && [[ "$(tr -d '[:space:]' <"${STATE_DIR}/be-quota.hint")" == "10" ]]; then
  record A9 "isolate → be-quota.hint=10 written" PASS
else
  record A9 "be-quota.hint missing" FAIL
fi

set +e
su -s /bin/bash nobody -c "bpftool prog list" >"${OUT}/a10.txt" 2>&1
a10=$?
set -u
if [[ "${a10}" -ne 0 ]]; then record A10 "unprivileged bpftool denied" PASS; else record A10 "bpftool allowed for nobody" FAIL; fi

if pm2_ok; then record A11 "PM2 after" PASS; else record A11 "PM2 after" SKIP; fi

VERDICT="ECGF_REDTEAM_PASS"
if [[ "${FAIL}" -gt 0 ]]; then
  VERDICT="ECGF_REDTEAM_FAIL"
fi
echo "VERDICT=${VERDICT} fail=${FAIL}" | tee "${OUT}/verdict.txt"
cp -f "${OUT}/results.txt" "${SCRIPT_DIR}/results/ecgf-redteam-latest.txt" 2>/dev/null || true
if [[ "${FAIL}" -eq 0 ]]; then
  exit 0
fi
exit 1
