#!/usr/bin/env bash
# Print steps to remove cursoragent from GitHub repo mentionable users.
set -euo pipefail
cat <<'EOF'
cursoragent appears because the Cursor GitHub App is installed on this repository.
It is NOT listed as a contributor — commits are Abdullah Hanif only.

Remove Cursor app access for this repo:
  1. Open https://github.com/settings/installations
  2. Click "Cursor" → Configure
  3. Under "Repository access", remove elite-ebpf-telemetry
     (or uninstall Cursor GitHub App if you do not need it)

Verify contributors (should be abdullahhanif-001 only):
  gh api repos/abdullahhanif-001/elite-ebpf-telemetry/contributors --jq '.[].login'

Use Abdullah Hanif git identity for pushes:
  bash scripts/setup-git-noreply.sh
EOF
