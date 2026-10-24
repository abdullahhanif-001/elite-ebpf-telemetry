#!/usr/bin/env bash
# adapt-sched-lab-local.sh — run sched-ext prep on THIS VM (not hardcoded VPS hostname).
# Usage: sudo bash scripts/research/adapt-sched-lab-local.sh deps|kernel-clone|...
set -euo pipefail
# shellcheck source=scripts/research/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

research_forbid_offline

ROOT="$(research_repo_root)"
export ELITE_SRC="${ELITE_SRC:-${ROOT}}"
export SCX_EXPECTED_HOST="${SCX_EXPECTED_HOST:-$(hostname)}"
export SCX_KERNEL_BUILD="${SCX_KERNEL_BUILD:-${HOME}/scx-kernel-build}"
export SCX_ROOT="${SCX_ROOT:-${HOME}/scx}"

echo "sched lab local: host=${SCX_EXPECTED_HOST} ELITE_SRC=${ELITE_SRC}"
echo "  SCX_KERNEL_BUILD=${SCX_KERNEL_BUILD}"
echo "  SCX_ROOT=${SCX_ROOT}"
exec bash "${ROOT}/scripts/server/sched-ext-vps-prep.sh" "${1:-verify}"
