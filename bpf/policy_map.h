/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef ELITE_POLICY_MAP_H
#define ELITE_POLICY_MAP_H

#include "vmlinux.h"
#include "bpf_helpers.h"

#define ELITE_POLICY_KEY_GLOBAL 0

#define ELITE_CAUSE_NONE    0
#define ELITE_CAUSE_NETWORK 1
#define ELITE_CAUSE_LLC     2
#define ELITE_CAUSE_PSI     3
#define ELITE_CAUSE_MIXED   4

struct elite_policy_value {
	__u64 policy_version;
	__u8 fault;
	__u8 cause;
	__u8 _pad[6];
	__u64 projected_ns;
	__u64 ewma_ns;
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 8);
	__type(key, __u32);
	__type(value, struct elite_policy_value);
} elite_policy SEC(".maps");

#endif /* ELITE_POLICY_MAP_H */
