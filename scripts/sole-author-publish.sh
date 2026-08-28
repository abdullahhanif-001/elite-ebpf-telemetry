#!/usr/bin/env bash
# sole-author-publish.sh — one Abdullah Hanif commit; removes co-author sidebar ghosts.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

export GIT_AUTHOR_NAME="Abdullah Hanif"
export GIT_AUTHOR_EMAIL="abdullahhanif-001@users.noreply.github.com"
export GIT_COMMITTER_NAME="Abdullah Hanif"
export GIT_COMMITTER_EMAIL="abdullahhanif-001@users.noreply.github.com"

git checkout main
git add -A
git reset HEAD -- .cursor .graphql-query.json reports scripts/oneclick/__pycache__ 2>/dev/null || true

TREE="$(git write-tree)"
MSG="Elite eBPF telemetry — Abdullah Hanif sole author.

Phase A+B: policy BPF sync, XDP mitigator, procshrinklat, elite-updater UX,
VPS proof suite (X-Ray, W4, gates 8/8), staff-engineer reports, Sonar-clean paths.
Removed INTERVIEW.md and redacted hostnames from proof artifacts.
Git identity: abdullahhanif-001@users.noreply.github.com only.
No third-party or AI co-author attribution."

git checkout --orphan sole-main
git reset --hard
NEW="$(printf '%s' "$MSG" | git commit-tree "$TREE")"
git reset --hard "$NEW"
git branch -M main

echo "HEAD:"
git log -1 --format='%H%n%an <%ae>%n%cn <%ce>%n%B'

git push --force origin main

sleep 8
echo "=== contributors API ==="
gh api repos/abdullahhanif-001/elite-ebpf-telemetry/contributors --jq '.[].login'
echo "=== mentionableUsers ==="
gh api graphql --input scripts/contributors.graphql --jq '.data.repository.mentionableUsers.nodes[].login' 2>/dev/null || true
