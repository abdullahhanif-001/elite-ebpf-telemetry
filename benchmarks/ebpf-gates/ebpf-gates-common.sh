#!/usr/bin/env bash
# ebpf-gates-common.sh — shared paths for global eBPF verification.
set -euo pipefail

ebpf_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

ebpf_repo_root() {
  cd "$(ebpf_script_dir)/../.." && pwd
}

OUR_GOAL_DIR="${OUR_GOAL_DIR:-$(ebpf_repo_root)/scripts/oneclick/results/our-goal}"
OUR_GOAL_MD="${OUR_GOAL_DIR}/OUR_GOAL.md"
OUR_GOAL_LOG="${OUR_GOAL_DIR}/run.log"

ebpf_ensure_our_goal() {
  mkdir -p "${OUR_GOAL_DIR}/audit" "${OUR_GOAL_DIR}/phases"
  if [[ ! -f "${OUR_GOAL_MD}" ]]; then
    cat > "${OUR_GOAL_MD}" <<'EOF'
# our-goal — Global eBPF Verification Ledger

| timestamp | phase | host | result | artifact | notes |
|-----------|-------|------|--------|----------|-------|
EOF
  fi
}

# Source our-goal-log if present
_EBPF_GATES_DIR="$(ebpf_script_dir)"
# shellcheck source=/dev/null
[[ -f "${_EBPF_GATES_DIR}/our-goal-log.sh" ]] && source "${_EBPF_GATES_DIR}/our-goal-log.sh"
