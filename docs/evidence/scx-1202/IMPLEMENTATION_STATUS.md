# SCX#1202 Implementation Status

**Last updated:** 2026-09-01  
**Primary proof target:** DigitalOcean VPS `143.244.164.216` (`ubuntu-s-4vcpu-8gb-nyc1`)  
**Required kernel:** sched_ext-enabled (e.g. `scx-dl-server` branch)  
**Evidence bundle:** [`VERIFICATION_*`](./) (latest dated directory from proof host)

## Completed (code in repo)

- [x] Layer 2 patch — [`contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`](../../contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch)
- [x] Layer 3 BPF — [`contrib/sched-ext/bpf/scx_rt_guard.bpf.h`](../../contrib/sched-ext/bpf/scx_rt_guard.bpf.h) + selftests
- [x] Gate scripts hardened — SKIP gates fail when `CONFIG_SCHED_CLASS_EXT=y`
- [x] `sched-ext-vps-prep.sh` — `scx-loader-build` phase
- [x] Static verifier — `scripts/verify-scx-1202-evidence.sh`

## Pending (DO VPS live proof)

- [ ] sched_ext kernel build + reboot on `143.244.164.216`
- [ ] Build `scx_loader` on VPS (`bash scripts/contabo/sched-ext-vps-prep.sh scx-loader-build`)
- [ ] `RT_GUARD_PASS fail=0` on DO (all gates, zero SKIP)
- [ ] Fresh `VERIFICATION_*` evidence bundle from DO hostname
- [ ] Reopen Layer 3 PR on sched-ext/scx (previous #3780 closed for dev)
- [ ] Issue [#1202](https://github.com/sched-ext/scx/issues/1202) closed after upstream merge

## Historical Contabo bundle

Earlier bundle under `VERIFICATION_20260901-045612/` was captured on Contabo (`vmi3469243`, kernel `6.19.0-rc7`) with G4/G6 SKIP — not accepted as full proof. DO re-run required.
