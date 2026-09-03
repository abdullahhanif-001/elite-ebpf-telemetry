# Stability Model

- elite-ecgf crash → systemd restart; Soft DCIC/agent independent.
- Envelope sticky files remain until explicit unlock.
- Never restart/stop Server PM2 apps; `pm2-guard.sh` before/after.
- Rollback: `systemctl disable --now elite-ecgf`; remove `/var/lib/elite/ecgf/sticky`.
