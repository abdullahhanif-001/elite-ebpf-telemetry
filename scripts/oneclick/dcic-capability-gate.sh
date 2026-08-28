#!/usr/bin/env bash
# Elite DCIC capability gate — selects Track A (soft) vs Track B (hard).
# Writes /etc/elite/dcic-capability.json. Safe on DigitalOcean guests (no RDT).
set -euo pipefail

OUT_JSON="${DCIC_CAPABILITY_OUT:-/etc/elite/dcic-capability.json}"
mkdir -p "$(dirname "${OUT_JSON}")" /var/lib/elite

HOST="$(hostname)"
KERNEL="$(uname -r)"
TRACK="A-soft"
TRACK_B_OK=false
REASONS=()

has_resctrl=false
has_l3_cat=false
has_sched_ext=false

if [[ -d /sys/fs/resctrl/info ]]; then
  has_resctrl=true
fi

if [[ -f /sys/fs/resctrl/info/L3/num_closids ]] || [[ -d /sys/fs/resctrl/info/L3 ]]; then
  has_l3_cat=true
fi

# Also detect CPUID leaves via /proc/cpuinfo flags when present
if grep -qw cat_l3 /proc/cpuinfo 2>/dev/null; then
  has_l3_cat=true
fi
if grep -qw rdt_a /proc/cpuinfo 2>/dev/null; then
  has_resctrl=true
fi

KCFG="/boot/config-${KERNEL}"
if [[ -f "${KCFG}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "${KCFG}"; then
  has_sched_ext=true
fi

if [[ "${has_resctrl}" == true && "${has_l3_cat}" == true ]]; then
  TRACK="B-hard"
  TRACK_B_OK=true
  REASONS+=("resctrl_l3_present")
else
  REASONS+=("no_resctrl_or_l3_cat")
fi

# Cloud KVM guests almost always lack CAT — force soft if hypervisor flag set
if grep -qw hypervisor /proc/cpuinfo 2>/dev/null && [[ "${TRACK_B_OK}" != true ]]; then
  TRACK="A-soft"
  REASONS+=("kvm_guest_soft_only")
fi

BTF=false
[[ -f /sys/kernel/btf/vmlinux ]] && BTF=true

REASONS_JSON="[]"
if [[ ${#REASONS[@]} -gt 0 ]]; then
  REASONS_JSON="$(printf '%s\n' "${REASONS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
fi

cat > "${OUT_JSON}" <<EOF
{
  "hostname": "${HOST}",
  "kernel": "${KERNEL}",
  "track": "${TRACK}",
  "track_b_ok": ${TRACK_B_OK},
  "has_resctrl": ${has_resctrl},
  "has_l3_cat": ${has_l3_cat},
  "has_sched_ext": ${has_sched_ext},
  "has_btf": ${BTF},
  "reasons": ${REASONS_JSON},
  "generated_at": "$(date -Is)",
  "hetzner_order_allowed": false,
  "hetzner_note": "Order AMD EPYC 7502P ONLY after Soft DCIC 100% ready (Milestone 5 / last day)."
}
EOF

echo "DCIC capability gate: track=${TRACK} -> ${OUT_JSON}"
cat "${OUT_JSON}"
# Exit 0 always — Soft Track A is a valid production path.
exit 0
