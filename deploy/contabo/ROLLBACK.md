# Elite Agent Rollback (Contabo)

Instant rollback — PM2/nginx untouched:

```bash
systemctl stop elite-agent && systemctl disable elite-agent
docker rm -f elite-prometheus elite-grafana 2>/dev/null || true
```

Verify PM2:

```bash
bash /opt/elite/scripts/pm2-guard.sh
pm2 list
```

Re-enable after fix:

```bash
systemctl enable elite-agent && systemctl start elite-agent
```

Baseline snapshots: `/opt/elite/baseline/`
