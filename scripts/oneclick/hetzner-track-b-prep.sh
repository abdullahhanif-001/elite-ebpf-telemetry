#!/usr/bin/env bash
# Track B prep for Hetzner AMD EPYC 7502P — DRY-RUN ONLY by default.
# NEVER places an order. Milestone 5 human step is separate and last-day only.
set -euo pipefail

CMD="${1:-dry-run}"

cat <<'EOF'
=== Elite DCIC Track B Prep (Hetzner AMD EPYC 7502P) ===
FORBIDDEN_TO_ORDER: This script never creates, bids, or pays for a Hetzner server.
Order is a MANUAL last-day action AFTER Soft DCIC is 100% ready.
EOF

case "${CMD}" in
  dry-run|status)
    echo "--- Preflight checklist (dry-run) ---"
    echo "[ ] Soft DCIC ready flag: /etc/elite/soft-dcic-ready"
    if [[ -f /etc/elite/soft-dcic-ready ]]; then
      echo "    FOUND:"
      cat /etc/elite/soft-dcic-ready
    else
      echo "    MISSING — do not order Hetzner yet"
    fi
    echo "[ ] Capability gate:"
    [[ -f /etc/elite/dcic-capability.json ]] && cat /etc/elite/dcic-capability.json || echo "    missing"
    echo
    echo "--- Day-of deploy plan (manual) ---"
    cat <<'PLAN'
1. Hetzner Robot/Auction: select AMD EPYC 7502P (32c/64t Zen 2).
2. Install Ubuntu 24.04; prefer kernel >= 6.12 if sched_ext desired.
3. SSH key auth; clone elite-ebpf-telemetry.
4. bash scripts/oneclick/dcic-capability-gate.sh
   Expect track=B-hard when /sys/fs/resctrl + L3 CAT present.
5. apt install intel-cmt-cat  # pqos-os works for AMD QoS via resctrl too on many kernels
6. mount -t resctrl resctrl /sys/fs/resctrl
7. Install Soft pack then switch elite-dcic to hard actuator (future):
   - Create CLOS via resctrl schemata
   - Map LC/BE tasks
8. Re-run soft-dcic-baseline.sh adapted for L3 thrash; publish density vs DO Track A.
PLAN
    echo "DRY_RUN_OK"
    exit 0
    ;;
  order)
    echo "REFUSED: automated order is disabled."
    echo "FORBIDDEN_TO_ORDER"
    echo "On the last day, a human must order AMD EPYC 7502P in the Hetzner UI."
    exit 2
    ;;
  *)
    echo "Usage: $0 {dry-run|status|order}"
    echo "  order -> always refused (manual last-day only)"
    exit 1
    ;;
esac
