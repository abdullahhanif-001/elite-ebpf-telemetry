/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
// +build ignore
// xdp_mitigator — cause-aware selective drop when fault=1 (network/mixed only).
#include "vmlinux.h"
#include "bpf_helpers.h"
#include "policy_map.h"

#ifndef XDP_PASS
#define XDP_PASS 2
#define XDP_DROP 1
#endif

SEC("xdp")
int xdp_mitigator(struct xdp_md *ctx)
{
	__u32 key = ELITE_POLICY_KEY_GLOBAL;
	struct elite_policy_value *val;

	(void)ctx;

	val = bpf_map_lookup_elem(&elite_policy, &key);
	if (!val || !val->fault)
		return XDP_PASS;

	if (val->cause == ELITE_CAUSE_NETWORK || val->cause == ELITE_CAUSE_MIXED)
		/* Actuate path: drop only when ELITE_XDP_ACTUATE=1 at load time via map default */
		return XDP_DROP;

	return XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";
