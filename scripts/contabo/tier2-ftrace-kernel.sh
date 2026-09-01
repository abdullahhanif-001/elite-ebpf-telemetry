#!/usr/bin/env bash
# tier2-ftrace-kernel.sh — separate-day ftrace kernel build (NO flood tests same session).
set -euo pipefail

export REAL_ONLY=1
KERNEL_BUILD="${SCX_KERNEL_BUILD:-/opt/scx-kernel-build}"
OUR_GOAL="${ELITE_SRC:-/opt/elite/src}/scripts/oneclick/results/our-goal"
mkdir -p "${OUR_GOAL}"

log() { echo "[tier2-ftrace] $*" | tee -a "${OUR_GOAL}/run.log"; }

if pgrep -f 'rt-guard-flood|stress-ng.*matrixprod' >/dev/null 2>&1; then
  log "FAIL: flood/stress running — stop before kernel build"
  exit 1
fi

cd "${KERNEL_BUILD}"
log "Enabling CONFIG_FUNCTION_TRACER..."
./scripts/config --enable CONFIG_FUNCTION_TRACER 2>/dev/null || true
./scripts/config --enable CONFIG_FTRACE 2>/dev/null || true
grep -E 'CONFIG_FUNCTION_TRACER|CONFIG_FTRACE' .config | tee -a "${OUR_GOAL}/run.log"

log "Building kernel package (make -j2 bindeb-pkg) — this takes ~30-90 min"
make -j2 bindeb-pkg 2>&1 | tee "${OUR_GOAL}/tier2-kernel-build.log"

DEB="$(ls -t ../*.deb 2>/dev/null | head -1)"
if [[ -z "${DEB}" ]]; then
  log "FAIL: no .deb produced"
  exit 1
fi
log "Installing ${DEB}..."
dpkg -i "${DEB}" || apt-get -f install -y

log "TIER2_BUILD_OK — REBOOT REQUIRED"
log "After reboot run: test -f /proc/sys/kernel/ftrace_enabled && echo FTRACE=YES"
log "Then: cd /opt/scx && cargo build --release -p scx_bpfland -p scx_lavd ..."
echo "TIER2_FTRACE_KERNEL_BUILD_OK deb=${DEB}" | tee "${OUR_GOAL}/tier2-ftrace-verdict.txt"
