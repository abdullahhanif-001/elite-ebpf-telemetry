#!/usr/bin/env bash
# Wrapper so systemd does not need shell-style env expansion in ExecStart.
set -euo pipefail
# shellcheck disable=SC1091
source /etc/elite/physics-pack/ebpf_exporter.env
exec /opt/elite/physics-pack/bin/ebpf_exporter \
  --config.dir="${EBPF_EXPORTER_CONFIG_DIR}" \
  --config.names="${EBPF_EXPORTER_CONFIG_NAMES}" \
  --web.listen-address="${EBPF_EXPORTER_LISTEN}"
