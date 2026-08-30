// SPDX-License-Identifier: GPL-2.0
/*
 * rt_guard_stress.bpf.c — minimal noop scheduler + rt_guard for kselftest.
 */
#include <scx/common.bpf.h>
#include <scx/compat.bpf.h>
#include <scx/scx_rt_guard.bpf.h>

char _license[] SEC("license") = "GPL";

SCX_RT_GUARD_SCHED_SWITCH_PROG(rt_guard_stress_switch)

s32 BPF_STRUCT_OPS(rt_guard_stress_enqueue, struct task_struct *p, u64 enq_flags)
{
	return scx_bpf_dsq_insert(p, SCX_DSQ_GLOBAL, SCX_SLICE_DFL, enq_flags);
}

void BPF_STRUCT_OPS(rt_guard_stress_dispatch, s32 cpu, struct task_struct *prev)
{
	scx_bpf_dsq_dispatch(SCX_DSQ_GLOBAL, SCX_SLICE_DFL, 0);
}

void BPF_STRUCT_OPS(rt_guard_stress_running, struct task_struct *p) {}
void BPF_STRUCT_OPS(rt_guard_stress_stopping, struct task_struct *p, bool runnable) {}
void BPF_STRUCT_OPS(rt_guard_stress_enable, struct task_struct *p) {}
void BPF_STRUCT_OPS(rt_guard_stress_disable, struct task_struct *p) {}

SCX_OPS_DEFINE(rt_guard_stress_ops,
	       .enqueue		= (void *)rt_guard_stress_enqueue,
	       .dispatch	= (void *)rt_guard_stress_dispatch,
	       .running		= (void *)rt_guard_stress_running,
	       .stopping	= (void *)rt_guard_stress_stopping,
	       .enable		= (void *)rt_guard_stress_enable,
	       .disable		= (void *)rt_guard_stress_disable,
	       .flags		= SCX_OPS_ENQ_EXITING,
	       .name		= "rt_guard_stress");
