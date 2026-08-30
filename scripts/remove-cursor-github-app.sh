#!/usr/bin/env bash
# Where to remove Cursor so cursoragent stops appearing on GitHub.
set -euo pipefail
cat <<'EOF'
cursoragent is NOT a code contributor — commits are Abdullah Hanif only.
It appears because Cursor IDE / Cloud Agents linked GitHub via OAuth.

You are on the RIGHT page but the WRONG tab.

On https://github.com/settings/applications

  Tab 1: "Installed GitHub Apps"     → often only SonarQubeCloud (NOT Cursor)
  Tab 2: "Authorized GitHub Apps"      → look for Cursor here → Revoke
  Tab 3: "Authorized OAuth Apps"       → look for Cursor here → Revoke  ← most common

Do all three tabs. Revoke Cursor anywhere it appears.

Also disconnect inside Cursor:

  1. Cursor: Ctrl+Shift+P → "Sign Out" (GitHub / Cursor account as needed)
  2. https://cursor.com/dashboard → Settings → Integrations → Disconnect GitHub
  3. Restart Cursor, sign in again with abdullahhanif-001 only

Repo-level check (optional):
  https://github.com/abdullahhanif-001/elite-ebpf-telemetry/settings/installations

Verify contributors (should be abdullahhanif-001 only):
  gh api repos/abdullahhanif-001/elite-ebpf-telemetry/contributors --jq '.[].login'

Verify mentionable users (cursoragent should disappear after revoke):
  gh api graphql --input scripts/contributors.graphql
EOF
