#!/usr/bin/env bash
# Install elite-ecgf binary + systemd unit (ADR-005). No novel BPF.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CMD="${1:-install}"

need_root() { [[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }; }

install_go_build() {
  mkdir -p /var/lib/elite/ecgf /usr/local/bin
  if command -v go >/dev/null 2>&1; then
    (cd "${REPO_ROOT}" && CGO_ENABLED=0 GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" go build -o /usr/local/bin/elite-ecgf ./cmd/elite-ecgf)
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${REPO_ROOT}:/src" -v /usr/local/bin:/out -w /src \
      -e CGO_ENABLED=0 -e GOTOOLCHAIN=auto \
      golang:1.23-bookworm go build -o /out/elite-ecgf ./cmd/elite-ecgf
  else
    echo "go or docker required to build elite-ecgf" >&2
    exit 1
  fi
  install -m 0644 "${REPO_ROOT}/deploy/server/elite-ecgf.service" /etc/systemd/system/elite-ecgf.service
  systemctl daemon-reload
  systemctl enable --now elite-ecgf.service
  echo "elite-ecgf installed"
}

case "${CMD}" in
  install) need_root; install_go_build ;;
  status)
    systemctl is-active elite-ecgf.service 2>/dev/null || echo "elite-ecgf: inactive"
    curl -sf --connect-timeout 1 127.0.0.1:9105/healthz && echo || true
    ;;
  uninstall)
    need_root
    systemctl disable --now elite-ecgf.service 2>/dev/null || true
    rm -f /etc/systemd/system/elite-ecgf.service /usr/local/bin/elite-ecgf
    systemctl daemon-reload
    ;;
  *) echo "usage: $0 install|status|uninstall" >&2; exit 1 ;;
esac
