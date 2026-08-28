#!/usr/bin/env bash
# setup-git-noreply.sh — Abdullah Hanif GitHub noreply identity (no Cursor agent email).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

NOREPLY="abdullahhanif-001@users.noreply.github.com"
NAME="Abdullah Hanif"

git config user.name "$NAME"
git config user.email "$NOREPLY"

# Prefer gh credential helper so pushes use abdullahhanif-001 PAT, not Cursor GitHub App.
if command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1; then
  gh auth setup-git -h github.com
fi

echo "Local git identity:"
git config user.name
git config user.email
echo "Push with: git push origin main  (or: bash scripts/sole-author-publish.sh)"
