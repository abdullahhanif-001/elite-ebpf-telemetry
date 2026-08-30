# RCA: cursoragent on GitHub (not a contributor)

## Root cause

`cursoragent` appears in GitHub **mentionable/assignee** lists because the **Cursor GitHub App** (`github.com/apps/cursor`) is installed on `elite-ebpf-telemetry` for Cloud Agents / Bugbot — **not** because of OAuth apps in user settings.

| Check | Result |
|-------|--------|
| Contributors | `abdullahhanif-001` only |
| Collaborators | `abdullahhanif-001` only |
| Commits by cursoragent | None |
| User Settings → OAuth Apps | GitHub CLI only (no Cursor) |
| User Settings → Installed Apps | SonarQube only |
| `mentionableUsers` GraphQL | `cursoragent` + `abdullahhanif-001` |

The Cursor app install lives at **github.com/apps/cursor/installations** or repo **Settings → Integrations** — not under personal Applications tabs.

## Fix (cache clear at source)

1. https://github.com/apps/cursor/installations → Configure → remove this repo  
2. https://github.com/abdullahhanif-001/elite-ebpf-telemetry/settings/installations → uninstall Cursor  
3. https://cursor.com/dashboard → Integrations → Disconnect GitHub  
4. Browser console (logged into cursor.com): `fetch('/api/dashboard/disconnect-github', {method: 'POST', credentials: 'include'})`  
5. Re-verify: `bash scripts/remove-cursor-github-app.sh`

If `cursoragent` persists after 24h: Cursor backend stale install — email **hi@cursor.com**.
