/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#ifndef ELITE_POLICY_MAP_H
#define ELITE_POLICY_MAP_H

#include "vmlinux.h"
#include "bpf_helpers.h"

#ifndef BPF_MAP_TYPE_RINGBUF
#define BPF_MAP_TYPE_RINGBUF 27
#endif
#ifndef BPF_MAP_TYPE_CPUMAP
#define BPF_MAP_TYPE_CPUMAP 20
#endif
#ifndef BPF_MAP_TYPE_DEVMAP
#define BPF_MAP_TYPE_DEVMAP 14
#endif

#define ELITE_POLICY_KEY_GLOBAL 0
#define ELITE_POLICY_VERSION_V2 2
#define ELITE_POLICY_VERSION_V3 3

#define ELITE_CAUSE_NONE    0
#define ELITE_CAUSE_NETWORK 1
#define ELITE_CAUSE_LLC     2
#define ELITE_CAUSE_PSI     3
#define ELITE_CAUSE_MIXED   4

#define ELITE_TIER_CRITICAL   0
#define ELITE_TIER_STANDARD   1
#define ELITE_TIER_BACKGROUND 2
#define ELITE_TIER_COUNT      3

#define ELITE_ESC_PORT_FILTER  (1 << 0)
#define ELITE_ESC_SYN_PROXY    (1 << 1)
#define ELITE_ESC_SOURCE_BLOCK (1 << 3)

#define ELITE_PPM_SCALE 1000000U
#define ELITE_LAMBDA_RING_BATCH 1024U

struct elite_policy_value {
	__u64 policy_version;
	__u8 fault;
	__u8 cause;
	__u8 actuate;
	__u8 _pad[5];
	__u64 projected_ns;
	__u64 ewma_ns;
	__u32 overload_ppm;
	__u32 shed_ppm;
	__u32 redirect_ifindex;
	__u32 tier_refill_ppm[4];
	__u32 mu_tokens_per_sec;
	__u64 rho_proj_ppm;
	__u32 escalate_flags;
	__u32 _pad_end;
};

struct elite_xdp_stat {
	__u64 pass;
	__u64 drop;
	__u64 redirect;
};

struct elite_token_bucket {
	__u64 tokens;
	__u64 last_refill_ns;
};

struct elite_lambda_event {
	__u64 ts_ns;
	__u32 pkt_count;
	__u32 syn_count;
	__u32 pass_count;
	__u32 drop_count;
};

struct elite_lpm_key {
	__u32 prefixlen;
	__u32 addr;
};

struct elite_port_key {
	__u16 port;
	__u16 _pad;
};

struct elite_src_key {
	__u32 src_ip;
	__u8 tier;
	__u8 _pad[3];
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 8);
	__type(key, __u32);
	__type(value, struct elite_policy_value);
} elite_policy SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct elite_xdp_stat);
} elite_xdp_stats SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_LRU_HASH);
	__uint(max_entries, 65536);
	__type(key, struct elite_src_key);
	__type(value, struct elite_token_bucket);
} elite_src_buckets SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 256);
	__type(key, struct elite_port_key);
	__type(value, __u8);
} elite_port_tier SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_LPM_TRIE);
	__uint(max_entries, 1024);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__type(key, struct elite_lpm_key);
	__type(value, __u8);
} elite_vip_lpm SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 4096);
	__type(key, __u32);
	__type(value, __u8);
} elite_src_block SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__uint(max_entries, 4);
	__type(key, __u32);
	__type(value, __u32);
} elite_devmap SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_CPUMAP);
	__uint(max_entries, 64);
	__type(key, __u32);
	__type(value, __u32);
} elite_cpumap SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} elite_lambda_ring SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} elite_pkt_counter SEC(".maps");

#endif /* ELITE_POLICY_MAP_H */
