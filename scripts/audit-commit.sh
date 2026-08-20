#!/usr/bin/env bash
# Reject commit messages that contain AI/agent watermarks or superadmin branding.
set -euo pipefail

MSG="${1:-}"
if [ -z "$MSG" ] && [ -f .git/COMMIT_EDITMSG ]; then
  MSG="$(cat .git/COMMIT_EDITMSG)"
fi
if [ -z "$MSG" ]; then
  echo "audit-commit: no message to check" >&2
  exit 1
fi

if echo "$MSG" | grep -Eiq '(co-authored-by|cursoragent|cursor agent|superadmin|claude|openai|gpt|copilot)'; then
  echo "audit-commit: REJECTED — message contains forbidden attribution (Abdullah Hanif only)" >&2
  exit 1
fi

echo "audit-commit: OK"
