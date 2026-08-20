#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

export GIT_AUTHOR_NAME="Abdullah Hanif"
export GIT_AUTHOR_EMAIL="abdullahhanif-001@users.noreply.github.com"
export GIT_COMMITTER_NAME="Abdullah Hanif"
export GIT_COMMITTER_EMAIL="abdullahhanif-001@users.noreply.github.com"

# Snapshot current tree from main
git checkout main
git add -A
# Drop local audit helpers from the squashed commit
git reset HEAD -- scripts/audit-contributors.sh scripts/audit-contributors-full.sh \
  scripts/contributors.graphql scripts/graphql-contributors.sh 2>/dev/null || true
git reset HEAD -- scripts/vps-govuln-full.sh scripts/vps-sca-rca.sh scripts/vps-tidy-build.sh 2>/dev/null || true

TREE=$(git write-tree)
MSG="Elite eBPF telemetry agent — Abdullah Hanif.

Single-author release history for abdullahhanif-001/elite-ebpf-telemetry."

# Orphan branch with one commit
git checkout --orphan squashed-main
git reset --hard
NEW=$(printf '%s' "$MSG" | git commit-tree "$TREE")
git reset --hard "$NEW"
git branch -M main

echo "New HEAD:"
git log -1 --format='%H%n%an <%ae>%n%B'

git push --force origin main

echo '=== post-push contributors ==='
gh api repos/abdullahhanif-001/elite-ebpf-telemetry/contributors --jq '.[].login'
sleep 5
gh api graphql -F query='query { repository(owner: "abdullahhanif-001", name: "elite-ebpf-telemetry") { mentionableUsers(first: 20) { nodes { login } } } }' --jq '.data.repository.mentionableUsers.nodes[].login'
