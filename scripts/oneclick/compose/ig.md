# compose-ig

Inspektor Gadget is installed by the Physics Pack. Extra gadgets (tcpdrop metrics, bpfstats):

```bash
sudo bash scripts/oneclick/elite-oneclick.sh enable ig
# optional: systemctl enable --now elite-ig-metrics.service
```

Attribution: `scripts/oneclick/ATTRIBUTION.md`.
