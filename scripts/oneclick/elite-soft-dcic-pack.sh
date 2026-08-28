#!/usr/bin/env bash
# Elite Soft DCIC Pack — Track A 1-click for DigitalOcean / VPS (no RDT required).
# Usage (root, Linux):
#   bash scripts/oneclick/elite-soft-dcic-pack.sh install
#   bash scripts/oneclick/elite-soft-dcic-pack.sh status
#   bash scripts/oneclick/elite-soft-dcic-pack.sh uninstall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

CMD="${1:-install}"
MODE="${DCIC_MODE:-observe}"
DCIC_ROOT="/opt/elite/dcic"
GO_VERSION="${GO_VERSION:-1.22.12}"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

log() { echo "[elite-soft-dcic] $*"; }

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    log "go present: $(go version)"
    return 0
  fi
  log "Installing Go ${GO_VERSION}..."
  local tar="go${GO_VERSION}.linux-amd64.tar.gz"
  curl -fsSL --proto '=https' --tlsv1.2 -o "/tmp/${tar}" "https://go.dev/dl/${tar}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${tar}"
  ln -sfn /usr/local/go/bin/go /usr/local/bin/go
  ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  log "go installed: $(go version)"
}

build_dcic() {
  ensure_go
  mkdir -p "${DCIC_ROOT}/bin" /var/lib/elite /etc/elite
  log "Building elite-dcic..."
  (
    cd "${REPO_ROOT}"
    CGO_ENABLED=0 /usr/local/bin/go build -o "${DCIC_ROOT}/bin/elite-dcic" ./cmd/elite-dcic
  )
  install -m 0755 "${DCIC_ROOT}/bin/elite-dcic" /usr/local/bin/elite-dcic
  log "elite-dcic -> /usr/local/bin/elite-dcic"
}

install_units() {
  cat > /etc/systemd/system/elite-dcic.service <<EOF
[Unit]
Description=Elite Soft DCIC Controller (Track A)
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
Environment=DCIC_MODE=${MODE}
ExecStart=/usr/local/bin/elite-dcic -mode ${MODE} -listen 127.0.0.1:9103 -capability /etc/elite/dcic-capability.json
Restart=on-failure
RestartSec=5
CPUQuota=3%
MemoryMax=64M
Nice=5
NoNewPrivileges=false
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now elite-dcic.service
}

run_gate() {
  bash "${SCRIPT_DIR}/dcic-capability-gate.sh"
}

do_install() {
  need_root
  [[ "$(uname -s)" == "Linux" ]] || { echo "Linux only"; exit 1; }
  run_gate
  build_dcic
  # Run controller unit tests (no root required for logic)
  (
    cd "${REPO_ROOT}"
    CGO_ENABLED=0 go test ./pkg/dcic/ -count=1
  )
  install_units
  # soft sensors helper
  install -m 0755 "${SCRIPT_DIR}/soft-dcic-sensors.sh" "${DCIC_ROOT}/bin/soft-dcic-sensors.sh" 2>/dev/null || true
  print_status
  cat <<EOF

Next:
  bash ${SCRIPT_DIR}/soft-dcic-proof.sh
  bash ${SCRIPT_DIR}/soft-dcic-baseline.sh
  # Modes: DCIC_MODE=advise|enforce bash $0 install   (reinstall unit)
  # Hetzner Track B: bash ${SCRIPT_DIR}/hetzner-track-b-prep.sh dry-run
EOF
}

print_status() {
  echo "=== Elite Soft DCIC status ==="
  [[ -f /etc/elite/dcic-capability.json ]] && cat /etc/elite/dcic-capability.json || echo "no capability json"
  systemctl is-active elite-dcic.service 2>/dev/null || echo "elite-dcic: inactive"
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 127.0.0.1:9103/metrics 2>/dev/null || echo 000)"
  echo "metrics :9103 -> ${code}"
  command -v elite-dcic >/dev/null && elite-dcic -h 2>&1 | head -n 3 || true
}

uninstall_pack() {
  need_root
  systemctl disable --now elite-dcic.service 2>/dev/null || true
  rm -f /etc/systemd/system/elite-dcic.service
  systemctl daemon-reload
  # fail-open: reset BE quota if cgroup exists
  if [[ -f /sys/fs/cgroup/elite-dcic/be/cpu.max ]]; then
    echo max 100000 > /sys/fs/cgroup/elite-dcic/be/cpu.max || true
  fi
  rm -f /usr/local/bin/elite-dcic
  log "soft dcic removed (capability json kept)"
}

case "${CMD}" in
  install) do_install ;;
  status) print_status ;;
  uninstall) uninstall_pack ;;
  gate) run_gate ;;
  *)
    echo "Usage: $0 {install|status|uninstall|gate}" >&2
    exit 1
    ;;
esac
