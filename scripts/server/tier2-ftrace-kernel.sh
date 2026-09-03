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
log "Ensuring sched_ext + BTF + ftrace in kernel config..."
./scripts/config --disable CONFIG_DEBUG_INFO_NONE 2>/dev/null || true
./scripts/config --enable CONFIG_DEBUG_INFO_DWARF5 2>/dev/null || true
./scripts/config --disable CONFIG_DEBUG_INFO_SPLIT 2>/dev/null || true
./scripts/config --disable CONFIG_DEBUG_INFO_REDUCED 2>/dev/null || true
./scripts/config --enable CONFIG_DEBUG_INFO_BTF 2>/dev/null || true
./scripts/config --enable CONFIG_BPF_SYSCALL 2>/dev/null || true
./scripts/config --enable CONFIG_BPF_JIT 2>/dev/null || true
./scripts/config --enable CONFIG_KPROBES 2>/dev/null || true
./scripts/config --enable CONFIG_FTRACE 2>/dev/null || true
./scripts/config --enable CONFIG_BPF_EVENTS 2>/dev/null || true
make olddefconfig
./scripts/config --enable CONFIG_SCHED_CLASS_EXT 2>/dev/null || true
./scripts/config --enable CONFIG_FUNCTION_TRACER 2>/dev/null || true
make olddefconfig
grep -E 'CONFIG_SCHED_CLASS_EXT|CONFIG_DEBUG_INFO_BTF|CONFIG_FUNCTION_TRACER' .config | tee -a "${OUR_GOAL}/run.log"

log "Building kernel packages (make -j2 bindeb-pkg) — ~30-90 min"
make -j2 bindeb-pkg LOCALVERSION=-scx-dl 2>&1 | tee "${OUR_GOAL}/tier2-kernel-build.log"

log "Installing kernel debs..."
dpkg -i ../*.deb 2>/dev/null || dpkg -i /opt/linux*.deb 2>/dev/null || true

KVER="$(ls -t /boot/vmlinuz-*scx-dl* 2>/dev/null | head -1 | sed 's|.*/vmlinuz-||')"
if [[ -n "${KVER}" && -f /etc/default/grub ]]; then
  python3 <<PY
import pathlib, re
p = pathlib.Path("/etc/default/grub")
t = p.read_text()
k = 'GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux ${KVER}"'
t = re.sub(r"^GRUB_DEFAULT=.*", k, t, flags=re.M) if re.search(r"^GRUB_DEFAULT=", t, re.M) else t.rstrip()+"\n"+k+"\n"
p.write_text(t)
print("GRUB_DEFAULT=${KVER}")
PY
  update-grub
fi

log "TIER2_BUILD_OK — REBOOT REQUIRED"
log "After reboot: test -f /proc/sys/kernel/ftrace_enabled && echo FTRACE=YES"
echo "TIER2_FTRACE_KERNEL_BUILD_OK kver=${KVER:-unknown}" | tee "${OUR_GOAL}/tier2-ftrace-verdict.txt"
