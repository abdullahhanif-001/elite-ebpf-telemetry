#!/usr/bin/env bash
# submit-rt-guard-upstream.sh — prepare Layer 2 LKML + Layer 3 scx PR submission pack.
# Does NOT send email or open PRs automatically; prints exact commands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRIB="${ROOT}/contrib/sched-ext"
OUT="${ROOT}/scripts/oneclick/results/upstream-submission-$(date +%Y%m%d)"
VERDICT="$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-*/verdict.txt 2>/dev/null | head -1 || true)"

mkdir -p "${OUT}"

if [[ -z "${VERDICT}" ]] || ! grep -q 'RT_GUARD_PASS' "${VERDICT}"; then
  echo "WARN: RT_GUARD_PASS verdict not found — run rt-guard-pass.sh on VPS first" >&2
else
  cp "${VERDICT}" "${OUT}/vps-verdict.txt"
  echo "VPS evidence: ${VERDICT}"
fi

# Layer 2: format-patch from contrib (or regenerate from VPS ext.c diff)
PATCH="${CONTRIB}/kernel/0001-sched_ext-rt-aware-watchdog.patch"
if [[ -f "${PATCH}" ]]; then
  cp "${PATCH}" "${OUT}/"
fi
cp "${CONTRIB}/LKML_COVER_LETTER.txt" "${OUT}/"
cp "${CONTRIB}/GITHUB_PR_BODY.md" "${OUT}/"
cp "${CONTRIB}/bpf/scx_rt_guard.bpf.h" "${OUT}/"
cp "${CONTRIB}/selftests/rt_guard_stress.c" "${OUT}/"
cp "${CONTRIB}/selftests/rt_guard_stress.bpf.c" "${OUT}/"

cat > "${OUT}/SUBMIT_COMMANDS.txt" <<EOF
# Layer 2 — LKML / sched_ext list
# Attach: ${OUT}/0001-sched_ext-rt-aware-watchdog.patch (or VPS ext.c diff via apply-rt-watchdog-patch.sh)
# Body: ${OUT}/LKML_COVER_LETTER.txt
# Evidence: ${OUT}/vps-verdict.txt
#
#   git send-email --to tj@kernel.org --to arighi@nvidia.com --to peterz@infradead.org \\
#     --subject "[PATCH] sched_ext: RT-aware watchdog stall detection (sched-ext/scx#1202)" \\
#     ${OUT}/0001-sched_ext-rt-aware-watchdog.patch
#
# Layer 3 — github.com/sched-ext/scx PR
# Fork sched-ext/scx, branch rt-guard, add:
#   - tools/sched_ext/include/scx/scx_rt_guard.bpf.h
#   - tools/testing/selftests/sched_ext/rt_guard_stress.{c,bpf.c}
# PR body: ${OUT}/GITHUB_PR_BODY.md
#
#   gh pr create --repo sched-ext/scx --title "sched_ext: Add scx_rt_guard RT preemption interceptor (fixes #1202)" \\
#     --body-file ${OUT}/GITHUB_PR_BODY.md
#
# Layer 1 — track only (Andrea Righi scx-dl-server); do not re-submit.
EOF

echo "SUBMISSION_PACK_OK out=${OUT}"
cat "${OUT}/SUBMIT_COMMANDS.txt"
