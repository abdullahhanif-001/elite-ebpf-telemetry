#!/usr/bin/env bash
# flood-safe-recovery.sh — kill stale flood jobs before safe phases.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/flood-common.sh"

pkill -9 -f rt-guard-heavy-flood 2>/dev/null || true
pkill -9 -f rt-guard-flood-phase 2>/dev/null || true
pkill -9 -f 'runner rt_stall' 2>/dev/null || true
pkill -9 -f 'runner rt_guard' 2>/dev/null || true
pkill -9 -f stress-ng 2>/dev/null || true
pkill -9 -f '/opt/scx/target/release/scx_' 2>/dev/null || true
sleep 2

echo "FLOOD_RECOVERY_OK"
uptime
free -h | head -2
swapon --show 2>/dev/null || true
pgrep make >/dev/null && echo "WARN: make still running" || echo "NO_BUILD_OK"
