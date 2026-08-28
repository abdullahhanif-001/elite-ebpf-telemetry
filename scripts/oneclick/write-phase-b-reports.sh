#!/usr/bin/env bash
# write-phase-b-reports.sh — aggregate Phase B VPS proofs into staff-engineer markdown.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
export ELITE_REPORT_STAMP="${ELITE_REPORT_STAMP:-$(date +%Y%m%d-%H%M%S)}"
export ELITE_BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"

python3 "${SCRIPT_DIR}/write-phase-b-reports.py"
