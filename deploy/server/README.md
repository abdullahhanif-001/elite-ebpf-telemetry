# Server / bare-metal VPS deploy

## Quick install

```bash
sudo bash install.sh --channel server --metal
```

## Required layout

- `/opt/elite/bin/elite-agent` — agent binary
- `/opt/elite/config/config.yaml` — use `deploy/server/config.yaml` (no `kernellatency` on 6.8+)
- `/opt/elite/logs/` — created by systemd `ExecStartPre`
- `/var/lib/elite/` — forecaster/ECGF state

## systemd units

| Unit | Use case |
|------|----------|
| `elite-agent.service` | K8s sidecar mode (`--sidecar`, pod env vars) |
| `elite-agent-metal.service` | Bare VPS without Kubernetes |

## Environment variables

| Variable | Required | Notes |
|----------|----------|-------|
| `INSPECTOR_NODENAME` | Recommended | Defaults to `%H` (hostname) in unit files |
| `KUBESKOOP_POD_NAMESPACE` | Sidecar only | Set in `elite-agent.service` |
| `KUBESKOOP_POD_NAME` | Sidecar only | Set in `elite-agent.service` |

## Verify

```bash
curl -s http://127.0.0.1:9102/metrics | grep -c '^elite_'
systemctl show elite-agent -p CapabilityBoundingSet,NoNewPrivileges
```
