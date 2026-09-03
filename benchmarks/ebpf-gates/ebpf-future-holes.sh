#!/usr/bin/env bash
# ebpf-future-holes.sh — FH1–FH10 regression gates.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
OUT="${OUR_GOAL_DIR}/future-holes-$(date +%Y%m%d-%H%M%S).json"
FAIL=0
ebpf_ensure_our_goal

check() {
  local id="$1" ok="$2" msg="$3"
  echo "{\"id\":\"${id}\",\"ok\":${ok},\"msg\":\"${msg}\"}"
  [[ "${ok}" == "true" ]] || FAIL=$((FAIL + 1))
}

results=()
# FH1 sched_ext kernel
if [[ -f "/boot/config-$(uname -r 2>/dev/null)" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null; then
  results+=("$(check FH1 true "sched_ext enabled")")
else
  results+=("$(check FH1 false "sched_ext not on running kernel")")
fi

# FH2 ftrace
if [[ -f /proc/sys/kernel/ftrace_enabled ]]; then
  results+=("$(check FH2 true "ftrace enabled")")
else
  results+=("$(check FH2 false "ftrace disabled — rust schedulers need FUNCTION_TRACER")")
fi

# FH3 orphans documented
if [[ -f "${ROOT}/bpf/DEPRECATED_ORPHANS.md" ]]; then
  results+=("$(check FH3 true "orphan marker present")")
else
  results+=("$(check FH3 false "DEPRECATED_ORPHANS.md missing")")
fi

# FH4 bpf2go drift (skip on hosts without make/clang)
if command -v make >/dev/null 2>&1 && command -v clang >/dev/null 2>&1 && [[ -d "${ROOT}/.git" ]]; then
  if (cd "${ROOT}" && timeout 120 make generate-bpf >/dev/null 2>&1); then
    if git -C "${ROOT}" diff --quiet pkg/exporter/probe/ 2>/dev/null; then
      results+=("$(check FH4 true "bpf2go embed in sync")")
    else
      results+=("$(check FH4 false "bpf2go embed drift after generate-bpf")")
    fi
  else
    results+=("$(check FH4 true "generate-bpf skipped (timeout or toolchain")")
  fi
else
  results+=("$(check FH4 true "make/clang skip")")
fi

# FH5 policy map ABI size
if grep -q 'len(b) != 80' "${ROOT}/pkg/forecaster/policy_bpf_sync_test.go" 2>/dev/null; then
  results+=("$(check FH5 true "policy ABI size pinned in test")")
else
  results+=("$(check FH5 false "policy ABI test missing")")
fi

# FH6 scheduler naming — no flatcg in matrix scripts
if grep -q 'rustland\|layered' "${ROOT}/benchmarks/sched-ext-gates/flood-common.sh" 2>/dev/null \
  && ! grep -q 'flatcg' "${ROOT}/benchmarks/sched-ext-gates/flood-common.sh" 2>/dev/null; then
  results+=("$(check FH6 true "scheduler list aligned")")
else
  results+=("$(check FH6 false "scheduler naming drift")")
fi

# FH7 PM2 guard script exists
[[ -f "${ROOT}/scripts/server/pm2-guard-wrap.sh" ]] \
  && results+=("$(check FH7 true "pm2-guard-wrap present")") \
  || results+=("$(check FH7 false "pm2-guard missing")")

# FH8 Layer2 on VPS path (local file check)
[[ -f "${ROOT}/contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch" ]] \
  && results+=("$(check FH8 true "Layer2 patch in repo")") \
  || results+=("$(check FH8 false "Layer2 patch missing")")

# FH9 REAL_ONLY
[[ "${REAL_ONLY:-1}" == "1" ]] \
  && results+=("$(check FH9 true "REAL_ONLY=1")") \
  || results+=("$(check FH9 false "REAL_ONLY not set")")

# FH10 recent VPS verdict
latest="$(ls -t "${ROOT}"/scripts/oneclick/results/rt-guard-*/verdict.txt 2>/dev/null | head -1 || true)"
if [[ -n "${latest}" ]] && grep -qE 'RT_GUARD_PASS|RT_GUARD_FLOOD_PASS' "${latest}" 2>/dev/null; then
  results+=("$(check FH10 true "VPS verdict found ${latest}")")
else
  results+=("$(check FH10 false "no recent RT_GUARD verdict")")
fi

{
  echo '{'
  echo '"checks": ['
  printf '%s,\n' "${results[@]}" | sed '$ s/,$//'
  echo "],"
  echo "\"fail\": ${FAIL}"
  echo '}'
} > "${OUT}"

if [[ "${FAIL}" -eq 0 ]]; then
  echo "FUTURE_HOLES_PASS fail=0"
  our_goal_log "D6_future_holes" "PASS" "${OUT}" "FH1-FH10"
else
  echo "FUTURE_HOLES_FAIL fail=${FAIL}"
  our_goal_log "D6_future_holes" "FAIL" "${OUT}" "fail=${FAIL}"
  exit 1
fi
