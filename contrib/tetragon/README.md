# contrib/tetragon — upstream PR material (Track 2)

## cilium/tetragon#5744 — mbset ID leak

**Problem:** Duplicate `matchBinaries` paths + early `RemoveID` lookup failure leaked followChildren IDs (64 cap).

**Fix (tested on VM):**

- `pkg/mbset/mbset.go` — tolerate `ebpf.ErrKeyNotExist`; release ID when `update == nil`
- `pkg/selectors/selectors.go` — dedupe paths in `WriteMatchBinariesPath`
- `pkg/selectors/matchbinaries_paths_test.go` — unit test

```bash
# Apply on tetragon clone
git apply contrib/tetragon/cilium-tetragon-5744-mbset.patch
go test ./pkg/selectors/ -run TestWriteMatchBinariesPathDedupes -count=1
```

**Open PR (from your GitHub account — agent token cannot fork cilium/tetragon):**

```bash
git clone https://github.com/cilium/tetragon.git
cd tetragon
git checkout -b fix/mbset-removeid-dup-path
git apply /path/to/elite-ebpf-telemetry/contrib/tetragon/cilium-tetragon-5744-mbset.patch
git commit -am "mbset: fix followChildren ID leak on duplicate paths"
git push origin fix/mbset-removeid-dup-path
gh pr create --repo cilium/tetragon --title "mbset: fix followChildren ID leak (duplicate paths)" --body "Fixes #5744. See test + dedupe + ErrKeyNotExist handling."
```

**VM verify from elite repo:**

```bash
TETRAGON_SRC=/path/to/tetragon bash scripts/verify-track1-track2-vm.sh
```
