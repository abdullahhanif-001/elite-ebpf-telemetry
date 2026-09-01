#!/usr/bin/env bash
# rt-guard-heavy-flood.sh — DEPRECATED: use rt-guard-flood-phase.sh + run-vps-flood-safe.ps1
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

GATES_DIR="$(script_dir)"
export FLOOD_SAFE_MODE=1

echo "WARN: rt-guard-heavy-flood.sh is deprecated — running safe sharded flood"
bash "${GATES_DIR}/flood-safe-recovery.sh"
bash "${GATES_DIR}/flood-safe-gate.sh"

for phase in P1 P2 P3 P4 P5; do
  echo "=== ${phase} ==="
  bash "${GATES_DIR}/rt-guard-flood-phase.sh" "${phase}" || exit 1
  sleep "${FLOOD_COOLDOWN_SEC:-60}"
done

bash "${GATES_DIR}/rt-guard-flood-aggregate.sh"
