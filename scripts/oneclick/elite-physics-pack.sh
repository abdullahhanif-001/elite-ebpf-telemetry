#!/usr/bin/env bash
# Elite One-Click Physics Pack — downloads GitHub/apt artifacts only (no Elite BPF inventions).
# Usage (on Linux VPS as root):
#   bash scripts/oneclick/elite-physics-pack.sh install
#   bash scripts/oneclick/elite-physics-pack.sh status
#   bash scripts/oneclick/elite-physics-pack.sh uninstall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

CMD="${1:-install}"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) EE_ARCH="x86_64"; IG_ARCH="amd64" ;;
  aarch64|arm64) EE_ARCH="aarch64"; IG_ARCH="arm64" ;;
  *) echo "Unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

log() { echo "[elite-physics-pack] $*"; }

download() {
  local url="$1" dest="$2"
  log "GET ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${url}"
  else
    wget -q -O "${dest}" "${url}"
  fi
}

install_dirs() {
  mkdir -p \
    "${PHYSICS_PACK_ROOT}"/{bin,ebpf_exporter,configs,prometheus,grafana,logs,src} \
    /etc/elite/physics-pack
  cp -f "${SCRIPT_DIR}/versions.env" /etc/elite/physics-pack/versions.env
  cp -f "${SCRIPT_DIR}/prometheus-scrape.yml" "${PHYSICS_PACK_ROOT}/prometheus/scrape.yml"
  cp -f "${SCRIPT_DIR}/grafana-elite-physics-pack.json" "${PHYSICS_PACK_ROOT}/grafana/"
  cp -f "${SCRIPT_DIR}/systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
  if [[ -d "${SCRIPT_DIR}/configs" ]]; then
    cp -a "${SCRIPT_DIR}/configs/." "${PHYSICS_PACK_ROOT}/configs/"
  fi
}

install_ebpf_exporter() {
  local tarball="ebpf_exporter_with_examples.${EE_ARCH}.tar.gz"
  local url="https://github.com/${EBPF_EXPORTER_REPO}/releases/download/${EBPF_EXPORTER_VERSION}/${tarball}"
  local tmp
  tmp="$(mktemp -d)"
  download "${url}" "${tmp}/${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "${tmp}"
  # Layout varies slightly; find binary + examples dir
  local bin
  bin="$(find "${tmp}" -type f -name 'ebpf_exporter' | head -n1)"
  if [[ -z "${bin}" ]]; then
    # bare binary release name
    download "https://github.com/${EBPF_EXPORTER_REPO}/releases/download/${EBPF_EXPORTER_VERSION}/ebpf_exporter.${EE_ARCH}" \
      "${PHYSICS_PACK_ROOT}/bin/ebpf_exporter"
    chmod +x "${PHYSICS_PACK_ROOT}/bin/ebpf_exporter"
    local ex_tar="examples.${EE_ARCH}.tar.gz"
    download "https://github.com/${EBPF_EXPORTER_REPO}/releases/download/${EBPF_EXPORTER_VERSION}/${ex_tar}" \
      "${tmp}/${ex_tar}"
    mkdir -p "${PHYSICS_PACK_ROOT}/ebpf_exporter/examples"
    tar -xzf "${tmp}/${ex_tar}" -C "${PHYSICS_PACK_ROOT}/ebpf_exporter/examples"
  else
    install -m 0755 "${bin}" "${PHYSICS_PACK_ROOT}/bin/ebpf_exporter"
    local exdir
    exdir="$(find "${tmp}" -type d -name 'examples' | head -n1)"
    if [[ -n "${exdir}" ]]; then
      rm -rf "${PHYSICS_PACK_ROOT}/ebpf_exporter/examples"
      mkdir -p "${PHYSICS_PACK_ROOT}/ebpf_exporter"
      cp -a "${exdir}" "${PHYSICS_PACK_ROOT}/ebpf_exporter/examples"
    fi
  fi
  rm -rf "${tmp}"
  log "ebpf_exporter ${EBPF_EXPORTER_VERSION} installed"
}

install_ig() {
  local tarball="ig-linux-${IG_ARCH}-${IG_VERSION}.tar.gz"
  local url="https://github.com/${IG_REPO}/releases/download/${IG_VERSION}/${tarball}"
  local tmp
  tmp="$(mktemp -d)"
  download "${url}" "${tmp}/${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "${tmp}"
  local bin
  bin="$(find "${tmp}" -type f -name 'ig' | head -n1)"
  if [[ -z "${bin}" ]]; then
    echo "ig binary not found in ${tarball}" >&2
    rm -rf "${tmp}"
    return 1
  fi
  install -m 0755 "${bin}" "${PHYSICS_PACK_ROOT}/bin/ig"
  ln -sfn "${PHYSICS_PACK_ROOT}/bin/ig" /usr/local/bin/ig
  rm -rf "${tmp}"
  log "inspektor-gadget ig ${IG_VERSION} installed"
}

install_bcc() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq "${BCC_APT_PACKAGE}" || log "WARN: apt install ${BCC_APT_PACKAGE} failed (optional)"
  else
    log "WARN: apt-get not found; skip ${BCC_APT_PACKAGE}"
  fi
}

optional_netstacklat_config() {
  if [[ "${NETSTACKLAT_OPTIONAL}" != "1" ]]; then
    return 0
  fi
  local dest="${PHYSICS_PACK_ROOT}/configs/netstacklat"
  mkdir -p "${dest}"
  download "https://raw.githubusercontent.com/${BPF_EXAMPLES_REPO}/${BPF_EXAMPLES_COMMIT}/netstacklat/netstacklat.yaml" \
    "${dest}/netstacklat.yaml"
  cat > "${dest}/README.md" <<EOF
# Optional netstacklat

Pinned config from ${BPF_EXAMPLES_REPO}@${BPF_EXAMPLES_COMMIT}.

To enable with ebpf_exporter you must build \`netstacklat.bpf.o\` upstream (not in Elite):

  git clone https://github.com/${BPF_EXAMPLES_REPO}.git
  cd bpf-examples && git checkout ${BPF_EXAMPLES_COMMIT}
  ./configure && make -C netstacklat

Then point a second exporter unit at this config dir. Default pack uses
Cloudflare prebuilt examples (softirq / kfree_skb / shrinklat) instead.
EOF
  log "vendored netstacklat.yaml (optional; not auto-started)"
}

write_exporter_env() {
  cat > /etc/elite/physics-pack/ebpf_exporter.env <<EOF
EBPF_EXPORTER_CONFIG_DIR=${PHYSICS_PACK_ROOT}/ebpf_exporter/examples
EBPF_EXPORTER_CONFIG_NAMES=${EBPF_EXPORTER_CONFIG_NAMES}
EBPF_EXPORTER_LISTEN=${EBPF_EXPORTER_LISTEN}
EOF
}

enable_units() {
  systemctl daemon-reload
  systemctl enable --now elite-ebpf-exporter.service || {
    log "WARN: elite-ebpf-exporter.service failed to start (kernel/BTF?). Check journalctl -u elite-ebpf-exporter"
  }
  log "systemd units enabled"
}

print_status() {
  echo "=== Elite Physics Pack status ==="
  echo "versions: ${PHYSICS_PACK_ROOT}/../.. (see /etc/elite/physics-pack/versions.env)"
  [[ -x "${PHYSICS_PACK_ROOT}/bin/ebpf_exporter" ]] && "${PHYSICS_PACK_ROOT}/bin/ebpf_exporter" --version 2>/dev/null || echo "ebpf_exporter: missing"
  [[ -x "${PHYSICS_PACK_ROOT}/bin/ig" ]] && "${PHYSICS_PACK_ROOT}/bin/ig" version 2>/dev/null || echo "ig: missing"
  echo "--- scrape endpoints ---"
  # host:port only — curl defaults to cleartext HTTP without a scheme:// literal (shell:S5332)
  for target in \
    "${ELITE_METRICS_LISTEN}/metrics" \
    "${EBPF_EXPORTER_LISTEN}/metrics" \
    "${IG_METRICS_LISTEN}/metrics"
  do
    code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "${target}" 2>/dev/null || echo 000)"
    echo "  ${target} -> ${code}"
  done
  systemctl is-active elite-agent.service 2>/dev/null || echo "elite-agent.service: not active (install Elite separately)"
  systemctl is-active elite-ebpf-exporter.service 2>/dev/null || echo "elite-ebpf-exporter.service: not active"
  command -v softirqs-bpfcc >/dev/null 2>&1 && echo "bcc: softirqs-bpfcc present" || echo "bcc: softirqs-bpfcc missing"
}

uninstall_pack() {
  need_root
  systemctl disable --now elite-ebpf-exporter.service 2>/dev/null || true
  rm -f /etc/systemd/system/elite-ebpf-exporter.service
  rm -f /etc/systemd/system/elite-ig-metrics.service /etc/systemd/system/elite-ig-metrics.path
  systemctl daemon-reload
  rm -rf "${PHYSICS_PACK_ROOT}" /etc/elite/physics-pack
  rm -f /usr/local/bin/ig
  log "physics pack removed (elite-agent left intact)"
}

do_install() {
  need_root
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "This installer targets Linux VPS/production servers." >&2
    exit 1
  fi
  install_dirs
  install_ebpf_exporter
  install_ig
  install_bcc
  optional_netstacklat_config
  write_exporter_env
  # Ensure systemd unit from repo is present even if copy earlier missed
  install -m 0644 "${SCRIPT_DIR}/systemd/elite-ebpf-exporter.service" /etc/systemd/system/elite-ebpf-exporter.service
  install -m 0755 "${SCRIPT_DIR}/systemd/run-ebpf-exporter.sh" "${PHYSICS_PACK_ROOT}/bin/run-ebpf-exporter.sh"
  if [[ -f "${SCRIPT_DIR}/systemd/elite-ig-metrics.service" ]]; then
    install -m 0644 "${SCRIPT_DIR}/systemd/elite-ig-metrics.service" /etc/systemd/system/elite-ig-metrics.service
  fi
  enable_units
  print_status
  cat <<EOF

Next:
  1. Ensure Elite agent is running on ${ELITE_METRICS_LISTEN}
  2. Merge ${PHYSICS_PACK_ROOT}/prometheus/scrape.yml into Prometheus
  3. Import ${PHYSICS_PACK_ROOT}/grafana/grafana-elite-physics-pack.json
  4. Prove: bash ${SCRIPT_DIR}/physics-pack-proof.sh

K8s path (optional): see ${SCRIPT_DIR}/k8s-oneclick.md
EOF
}

case "${CMD}" in
  install) do_install ;;
  status) print_status ;;
  uninstall) uninstall_pack ;;
  *)
    echo "Usage: $0 {install|status|uninstall}" >&2
    exit 1
    ;;
esac
