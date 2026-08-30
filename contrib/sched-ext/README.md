# contrib/sched-ext — Upstream RT Monopolization Fix

Separate from Elite product code (ADR-005). Kernel + BPF scheduler contributions
for [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202).

## Three Layers

| Layer | Artifact | Location |
|-------|----------|----------|
| 1 ext_server DL server | Andrea Righi v12 patchset | `arighi/linux` branch `scx-dl-server` |
| 2 RT-aware watchdog | `0001-sched_ext-rt-aware-watchdog.patch` | `kernel/` |
| 3 BPF preemption interceptor | `scx_rt_guard.bpf.h` | `bpf/` |
| Selftest | `rt_guard_stress.c` | `selftests/` |

## VPS Test (REAL_ONLY=1)

```bash
# Deploy from dev machine
bash benchmarks/sched-ext-gates/deploy-to-vps.sh

# One-time VPS prep (swap, kernel build, scx clone)
ssh contabo-server 'bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh swap'
ssh contabo-server 'bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh deps'
ssh contabo-server 'bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh kernel-clone'
ssh contabo-server 'bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh kernel-config'
ssh contabo-server 'nohup bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh kernel-build > /tmp/scx-kernel-build.log 2>&1 &'

# After reboot into scx-dl kernel:
bash benchmarks/sched-ext-gates/rt-guard-pass.sh
```

## References

- [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)
- [LWN sched_ext overview](https://lwn.net/Articles/1055970/)
- [Linux commit a3f5d482](https://github.com/torvalds/linux/commit/a3f5d48222532484c1e85ef27cc6893803e4cd17)
