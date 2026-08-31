#!/usr/bin/env bash
# sched-ext-vps-prep.sh — one-time VPS prep: swap, toolchain, kernel, scx, patches.
# Run ON VPS: bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh [phase]
# Phases: all | swap | deps | kernel-clone | kernel-config | kernel-build | kernel-install | scx-clone | scx-build | apply-patches | verify
set -euo pipefail

export REAL_ONLY=1
[[ "${REAL_ONLY}" == "1" ]] || { echo "FAIL mock forbidden"; exit 1; }

PHASE="${1:-all}"
SCX_KERNEL_BUILD="${SCX_KERNEL_BUILD:-/opt/scx-kernel-build}"
SCX_ROOT="${SCX_ROOT:-/opt/scx}"
CONTRIB="${ELITE_SRC:-/opt/elite/src}/contrib/sched-ext"
KERNEL_GIT="${KERNEL_GIT:-https://git.kernel.org/pub/scm/linux/kernel/git/arighi/linux.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-scx-dl-server}"
BUILD_JOBS="${BUILD_JOBS:-2}"
SWAP_SIZE_GB="${SWAP_SIZE_GB:-4}"
FALLBACK_KERNEL="${FALLBACK_KERNEL:-6.8.0-138-generic}"

log() { echo "[sched-ext-prep] $*"; }

phase_swap() {
  if swapon --show | grep -q /swapfile; then
    log "swap already active"
    return 0
  fi
  log "creating ${SWAP_SIZE_GB}G swapfile"
  fallocate -l "${SWAP_SIZE_GB}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB * 1024))
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  swapon --show
}

phase_deps() {
  log "installing build dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    build-essential libbpf-dev libelf-dev dwarves pahole flex bison bc \
    libssl-dev rsync cpio python3 stress-ng git \
    bpfcc-tools linux-tools-common linux-tools-generic \
    libcap-dev libcap2-bin pkg-config \
    debhelper libdw-dev libncurses-dev libncursesw5-dev \
    zstd libzstd-dev dwarves
}

phase_kernel_clone() {
  log "cloning kernel ${KERNEL_BRANCH}"
  if [[ -d "${SCX_KERNEL_BUILD}/.git" ]]; then
    cd "${SCX_KERNEL_BUILD}"
    git fetch origin "${KERNEL_BRANCH}" 2>/dev/null || git fetch --all
    git checkout "${KERNEL_BRANCH}" 2>/dev/null || git checkout -b "${KERNEL_BRANCH}" "origin/${KERNEL_BRANCH}"
    git pull --ff-only 2>/dev/null || true
  else
    rm -rf "${SCX_KERNEL_BUILD}"
    git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_GIT}" "${SCX_KERNEL_BUILD}" || {
      log "shallow clone failed — trying full clone"
      git clone --branch "${KERNEL_BRANCH}" "${KERNEL_GIT}" "${SCX_KERNEL_BUILD}"
    }
  fi
}

phase_kernel_config() {
  cd "${SCX_KERNEL_BUILD}"
  log "configuring kernel"
  make defconfig
  ./scripts/config --enable CONFIG_SCHED_CLASS_EXT
  ./scripts/config --enable CONFIG_BPF_SYSCALL
  ./scripts/config --enable CONFIG_BPF_JIT
  ./scripts/config --enable CONFIG_DEBUG_INFO_BTF
  ./scripts/config --enable CONFIG_DEBUG_INFO
  ./scripts/config --enable CONFIG_KPROBES
  ./scripts/config --enable CONFIG_FTRACE
  ./scripts/config --enable CONFIG_BPF_EVENTS
  ./scripts/config --set-val CONFIG_MODULE_COMPRESS_NONE y
  make olddefconfig
  grep CONFIG_SCHED_CLASS_EXT .config
}

phase_kernel_build() {
  cd "${SCX_KERNEL_BUILD}"
  log "building kernel packages (jobs=${BUILD_JOBS}) — may take 1-3 hours"
  make -j"${BUILD_JOBS}" bindeb-pkg LOCALVERSION=-scx-dl
}

phase_kernel_install() {
  cd "${SCX_KERNEL_BUILD}"
  log "installing kernel debs"
  dpkg -i ../linux-*.deb 2>/dev/null || dpkg -i ../*.deb
  # Keep stock kernel as GRUB default (fallback)
  if [[ -f /etc/default/grub ]]; then
    sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${FALLBACK_KERNEL}\"/" /etc/default/grub || true
    update-grub
  fi
  log "kernel installed — reboot required: reboot"
  log "after reboot run: bash ${ELITE_SRC:-/opt/elite/src}/scripts/contabo/sched-ext-vps-prep.sh verify"
}

phase_scx_clone() {
  log "cloning sched-ext/scx"
  if [[ -d "${SCX_ROOT}/.git" ]]; then
    cd "${SCX_ROOT}" && git pull --ff-only || true
  else
    git clone --depth 1 https://github.com/sched-ext/scx.git "${SCX_ROOT}"
  fi
}

phase_scx_build() {
  cd "${SCX_ROOT}"
  log "building scx rust schedulers (bpfland lavd rusty flash rustland layered)"
  apt-get install -y -qq libseccomp-dev lld clang llvm pkg-config libelf-dev libbpf-dev 2>/dev/null || true
  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable || true
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi
  rustc --version || { log "FAIL rustc missing"; return 1; }
  for sched in bpfland lavd rusty flash rustland layered; do
    dir="${SCX_ROOT}/scheds/rust/scx_${sched}"
    if [[ -d "${dir}" ]]; then
      log "cargo build scx_${sched}"
      (cd "${dir}" && cargo build --release) 2>&1 || log "WARN scx_${sched} build failed"
    fi
  done
  ls -la "${SCX_ROOT}/target/release/scx_"* 2>/dev/null || log "no scx binaries yet"
}

phase_apply_patches() {
  log "applying contrib patches (Layer 2 watchdog + Layer 3 selftest)"
  if [[ ! -d "${CONTRIB}" ]]; then
    log "WARN contrib not at ${CONTRIB}"
    return 0
  fi
  cd "${SCX_KERNEL_BUILD}"
  if [[ -f "${CONTRIB}/kernel/0001-sched_ext-rt-aware-watchdog.patch" ]]; then
    patch -p1 --forward --dry-run < "${CONTRIB}/kernel/0001-sched_ext-rt-aware-watchdog.patch" && \
      patch -p1 --forward < "${CONTRIB}/kernel/0001-sched_ext-rt-aware-watchdog.patch" || log "watchdog patch already applied or failed"
  fi
  # Install contrib selftests
  if [[ -f "${CONTRIB}/selftests/rt_guard_stress.c" ]]; then
    cp "${CONTRIB}/selftests/rt_guard_stress.c" tools/testing/selftests/sched_ext/
    cp "${CONTRIB}/selftests/rt_guard_stress.bpf.c" tools/testing/selftests/sched_ext/ 2>/dev/null || true
    if ! grep -q rt_guard_stress tools/testing/selftests/sched_ext/Makefile; then
      if [[ -f "${ELITE_SRC}/scripts/contabo/patch-sched-ext-makefile.py" ]]; then
        python3 "${ELITE_SRC}/scripts/contabo/patch-sched-ext-makefile.py"
      else
        python3 - <<'PY'
import pathlib
p = pathlib.Path("/opt/scx-kernel-build/tools/testing/selftests/sched_ext/Makefile")
lines = p.read_text().splitlines()
out = []
for line in lines:
    out.append(line)
    if line.rstrip(" \\").endswith("rt_stall"):
        out.append("\trt_guard_stress\t\t\t\\")
p.write_text("\n".join(out) + "\n")
print("Makefile updated")
PY
      fi
    fi
  fi
  if [[ -f "${CONTRIB}/bpf/scx_rt_guard.bpf.h" ]]; then
    mkdir -p tools/sched_ext/include/scx
    cp "${CONTRIB}/bpf/scx_rt_guard.bpf.h" tools/sched_ext/include/scx/
  fi
  log "patches applied — rebuild kernel if watchdog patch was new"
}

phase_verify() {
  log "verify sched_ext"
  k="$(uname -r)"
  echo "kernel=${k}"
  if [[ -f "/boot/config-${k}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-${k}"; then
    echo "sched_ext=YES"
  else
    echo "sched_ext=NO — reboot into scx-dl kernel or rerun kernel-install"
    exit 1
  fi
  command -v scx_loader && echo "scx_loader=YES" || echo "scx_loader=NO"
  swapon --show
  mkdir -p /opt/elite/baseline
  pm2 jlist > /opt/elite/baseline/pm2-before.json 2>/dev/null || true
  echo "VERIFY_OK"
}

run_phase() {
  case "$1" in
    swap) phase_swap ;;
    deps) phase_deps ;;
    kernel-clone) phase_kernel_clone ;;
    kernel-config) phase_kernel_config ;;
    kernel-build) phase_kernel_build ;;
    kernel-install) phase_kernel_install ;;
    scx-clone) phase_scx_clone ;;
    scx-build) phase_scx_build ;;
    apply-patches) phase_apply_patches ;;
    verify) phase_verify ;;
    all)
      phase_swap
      phase_deps
      phase_kernel_clone
      phase_kernel_config
      phase_kernel_build
      phase_kernel_install
      phase_scx_clone
      phase_apply_patches
      log "REBOOT REQUIRED — then run: $0 verify && $0 scx-build"
      ;;
    *) echo "unknown phase: $1"; exit 1 ;;
  esac
}

run_phase "${PHASE}"
