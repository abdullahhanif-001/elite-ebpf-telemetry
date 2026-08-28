# Contabo / metal rollback

## Instant agent off

```bash
sudo systemctl stop elite-agent
sudo systemctl disable elite-agent
```

## Auto-update rollback (binary)

Updater keeps the prior binary at `/opt/elite/bin/previous/elite-agent`.

```bash
sudo systemctl stop elite-agent
sudo cp -f /opt/elite/bin/previous/elite-agent /opt/elite/bin/elite-agent
sudo systemctl start elite-agent
curl -fsS http://127.0.0.1:9102/metrics | head
```

Disable auto-update:

```bash
sudo systemctl disable --now elite-updater.timer
```

## Optional docker observability

```bash
docker rm -f elite-prometheus elite-grafana 2>/dev/null || true
```

## Verify co-resident apps

```bash
bash /opt/elite/scripts/pm2-guard.sh
pm2 list
```

## Re-enable

```bash
sudo systemctl enable --now elite-agent
sudo systemctl enable --now elite-updater.timer   # optional
```

Baseline configs (if saved): `/opt/elite/baseline/`.
