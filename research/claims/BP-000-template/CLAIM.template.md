# Filing a new claim (copy to BP-00N)

1. Run on the **same** machine as repro:
   ```bash
   RESEARCH_PREFLIGHT_OUT=research/claims/BP-00N/00-preflight.json \
     bash scripts/research/live-preflight.sh
   ```
2. Add `repro/`, `load.log`, `dmesg.txt` (if kernel impact), `IMPACT.md`, `MANIFEST.json`.
3. Verify:
   ```bash
   bash scripts/research/bypass-claim-verify.sh research/claims/BP-00N
   ```

Impact must match evidence. `TEST-INFRA` patches must be named in `IMPACT.md`.
