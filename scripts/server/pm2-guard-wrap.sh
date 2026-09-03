#!/usr/bin/env bash
# pm2-guard-wrap.sh — run strict PM2 guards before/after each phase; abort on drift.
# Fresh VPS without PM2: N/A (exit 0), not FAIL.
set -euo pipefail

WHEN="${1:?usage: $0 before|after <phase-name>}"
LABEL="${2:?usage: $0 before|after <phase-name>}"
BASE="/opt/elite/baseline/pm2-before.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "PM2_WRAP ${WHEN} ${LABEL}"

if ! command -v pm2 >/dev/null 2>&1; then
  echo "PM2_WRAP_N/A_NO_PM2 ${WHEN} ${LABEL}"
  exit 0
fi

if [[ ! -f "${BASE}" ]]; then
  mkdir -p "$(dirname "${BASE}")"
  pm2 jlist >"${BASE}" 2>/dev/null || echo '[]' >"${BASE}"
  echo "PM2_WRAP_N/A_BASELINE_CREATED ${WHEN} ${LABEL}"
fi

if [[ -x "${REPO_ROOT}/scripts/oneclick/elite-pm2-uninstall-guard.sh" ]]; then
  bash "${REPO_ROOT}/scripts/oneclick/elite-pm2-uninstall-guard.sh" "${BASE}" "${WHEN}-${LABEL}" || true
fi
bash "${REPO_ROOT}/deploy/server/pm2-guard.sh"

echo "PM2_WRAP_OK ${WHEN} ${LABEL}"
