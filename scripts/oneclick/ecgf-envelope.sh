#!/usr/bin/env bash
# ECGF consequence envelope — compose systemd restrictions (no novel BPF).
# Usage: bash ecgf-envelope.sh run -- <command...>
#        bash ecgf-envelope.sh write-profiles
# NOTE: avoid `set -e` + `[[ cond ]] &&` patterns (false [[ aborts).
set -uo pipefail
# SCRIPT_DIR retained for compose-relative helpers / future profile templates.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SCRIPT_DIR}"
STATE_DIR="${ELITE_ECGF_DIR:-/var/lib/elite/ecgf}"
POSTURE_FILE="${STATE_DIR}/posture.json"
mkdir -p "${STATE_DIR}/profiles"

posture_level() {
  if [[ -n "${ELITE_ECGF_FORCE_POSTURE:-}" ]]; then
    echo "${ELITE_ECGF_FORCE_POSTURE}"
    return 0
  fi
  if [[ -f "${POSTURE_FILE}" ]]; then
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("posture",0))' "${POSTURE_FILE}" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_profiles() {
  local p
  p="$(posture_level)"
  cat >"${STATE_DIR}/profiles/env.sh" <<EOF
#!/usr/bin/env bash
# shellcheck shell=bash
# generated posture=${p}
export ELITE_ECGF_POSTURE=${p}
EOF
  case "${p}" in
    2)
      # Isolate: no net + drop to nobody + hide secrets (compose primitives, not novel BPF)
      cat >"${STATE_DIR}/profiles/systemd-props.txt" <<'EOF'
PrivateNetwork=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
MemoryMax=64M
User=nobody
Group=nogroup
InaccessiblePaths=/etc/shadow
InaccessiblePaths=/root/.ssh
EOF
      ;;
    1)
      cat >"${STATE_DIR}/profiles/systemd-props.txt" <<'EOF'
ProtectHome=yes
NoNewPrivileges=yes
MemoryMax=96M
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
User=nobody
Group=nogroup
InaccessiblePaths=/etc/shadow
EOF
      ;;
    *)
      cat >"${STATE_DIR}/profiles/systemd-props.txt" <<'EOF'
NoNewPrivileges=yes
MemoryMax=128M
EOF
      ;;
  esac
  echo "wrote profiles posture=${p}"
}

run_cmd() {
  write_profiles
  local props=()
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" || "${line}" =~ ^# ]]; then
      continue
    fi
    props+=("-p" "${line}")
  done <"${STATE_DIR}/profiles/systemd-props.txt"
  if command -v systemd-run >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]]; then
    timeout 12 systemd-run --quiet --collect --wait --pipe "${props[@]}" -- "$@"
  else
    echo "WARN: systemd-run unavailable; running with env only" >&2
    # shellcheck source=/dev/null
    source "${STATE_DIR}/profiles/env.sh"
    "$@"
  fi
}

cmd="${1:-write-profiles}"
shift || true
case "${cmd}" in
  write-profiles) write_profiles ;;
  run)
    if [[ "${1:-}" == "--" ]]; then shift; fi
    run_cmd "$@"
    ;;
  *)
    echo "usage: $0 write-profiles|run -- <cmd>" >&2
    exit 1
    ;;
esac
