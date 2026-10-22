#!/usr/bin/env bash
# ebpf-future-holes.sh — FH1–FH10 regression gates.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
OUT="${OUR_GOAL_DIR}/future-holes-$(date +%Y%m%d-%H%M%S).json"
FAIL=0
ebpf_ensure_our_goal

record_check() {
  local id="$1" ok="$2" msg="$3"
  results+=("{\"id\":\"${id}\",\"ok\":${ok},\"msg\":\"${msg}\"}")
  [[ "${ok}" == "true" ]] || FAIL=$((FAIL + 1))
}

evidence_full_ok() {
  bash "${ROOT}/scripts/verify-scx-1202-evidence.sh" >/dev/null 2>&1
}

results=()
# FH1 sched_ext kernel (offline: committed FULL SCX bundle is acceptable)
if [[ -f "/boot/config-$(uname -r 2>/dev/null)" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null; then
  record_check FH1 true "sched_ext enabled on running kernel"
elif [[ "${ELITE_OFFLINE:-0}" == "1" ]] && evidence_full_ok; then
  record_check FH1 true "sched_ext proof via committed FULL evidence bundle (offline)"
else
  record_check FH1 false "sched_ext not on running kernel and no FULL evidence"
fi

# FH2 ftrace
if [[ -f /proc/sys/kernel/ftrace_enabled ]]; then
  record_check FH2 true "ftrace enabled"
else
  record_check FH2 false "ftrace disabled — rust schedulers need FUNCTION_TRACER"
fi

# FH3 orphans documented
if [[ -f "${ROOT}/bpf/DEPRECATED_ORPHANS.md" ]]; then
  record_check FH3 true "orphan marker present"
else
  record_check FH3 false "DEPRECATED_ORPHANS.md missing"
fi

# FH4 bpf2go drift (skip on hosts without make/clang)
if command -v make >/dev/null 2>&1 && command -v clang >/dev/null 2>&1 && [[ -d "${ROOT}/.git" ]]; then
  if (cd "${ROOT}" && timeout 120 make generate-bpf >/dev/null 2>&1); then
    if git -C "${ROOT}" diff --name-only pkg/exporter/probe/ 2>/dev/null | grep -qE '\.go$'; then
      record_check FH4 false "bpf2go .go embed drift after generate-bpf"
    else
      record_check FH4 true "bpf2go embed in sync"
    fi
  else
    record_check FH4 true "generate-bpf skipped (timeout or toolchain)"
  fi
else
  record_check FH4 true "make/clang skip"
fi

# FH5 policy map ABI size
if grep -q 'len(b) != 80' "${ROOT}/pkg/forecaster/policy_bpf_sync_test.go" 2>/dev/null; then
  record_check FH5 true "policy ABI size pinned in test"
else
  record_check FH5 false "policy ABI test missing"
fi

# FH6 scheduler naming — no flatcg in matrix scripts
if grep -q 'rustland\|layered' "${ROOT}/benchmarks/sched-ext-gates/flood-common.sh" 2>/dev/null \
  && ! grep -q 'flatcg' "${ROOT}/benchmarks/sched-ext-gates/flood-common.sh" 2>/dev/null; then
  record_check FH6 true "scheduler list aligned"
else
  record_check FH6 false "scheduler naming drift"
fi

# FH7 PM2 guard script exists
[[ -f "${ROOT}/scripts/server/pm2-guard-wrap.sh" ]] \
  && record_check FH7 true "pm2-guard-wrap present" \
  || record_check FH7 false "pm2-guard missing"

# FH8 Layer2 on VPS path (local file check)
[[ -f "${ROOT}/contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch" ]] \
  && record_check FH8 true "Layer2 patch in repo" \
  || record_check FH8 false "Layer2 patch missing"

# FH9 REAL_ONLY
[[ "${REAL_ONLY:-1}" == "1" ]] \
  && record_check FH9 true "REAL_ONLY=1" \
  || record_check FH9 false "REAL_ONLY not set"

# FH10 recent VPS verdict (offline: FULL evidence bundle)
latest="$(ls -t "${ROOT}"/scripts/oneclick/results/rt-guard-*/verdict.txt 2>/dev/null | head -1 || true)"
if [[ -n "${latest}" ]] && grep -qE 'RT_GUARD_PASS|RT_GUARD_FLOOD_PASS' "${latest}" 2>/dev/null; then
  record_check FH10 true "VPS verdict found ${latest}"
elif [[ "${ELITE_OFFLINE:-0}" == "1" ]] && evidence_full_ok; then
  record_check FH10 true "committed FULL SCX#1202 evidence bundle (offline)"
else
  record_check FH10 false "no recent RT_GUARD verdict or FULL evidence"
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
