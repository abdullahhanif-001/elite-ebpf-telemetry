/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
// +build ignore
// xdp_mitigator v3 — token-bucket admission, tier priority, DEVMAP redirect, ringbuf λ.
#include "vmlinux.h"
#include "bpf_helpers.h"
#include "policy_map.h"
#include "headers/bpf/bpf_endian.h"

#ifndef XDP_PASS
#define XDP_PASS 2
#define XDP_DROP 1
#define XDP_REDIRECT 4
#endif

#define ETH_P_IP 0x0800
#define IPPROTO_TCP 6
#define TCP_FLAG_SYN 0x02

static __always_inline void xdp_bump_stat(__u64 pass, __u64 drop, __u64 redir)
{
	__u32 k = 0;
	struct elite_xdp_stat *st = bpf_map_lookup_elem(&elite_xdp_stats, &k);
	if (!st)
		return;
	if (pass)
		st->pass += pass;
	if (drop)
		st->drop += drop;
	if (redir)
		st->redirect += redir;
}

static __always_inline void maybe_emit_lambda(__u32 syn, __u32 pass, __u32 drop)
{
	__u32 k = 0;
	__u64 *cnt = bpf_map_lookup_elem(&elite_pkt_counter, &k);
	if (!cnt)
		return;
	(*cnt)++;
	if ((*cnt) % ELITE_LAMBDA_RING_BATCH != 0)
		return;

	struct elite_lambda_event *ev;
	ev = bpf_ringbuf_reserve(&elite_lambda_ring, sizeof(*ev), 0);
	if (!ev)
		return;
	ev->ts_ns = bpf_ktime_get_ns();
	ev->pkt_count = ELITE_LAMBDA_RING_BATCH;
	ev->syn_count = syn;
	ev->pass_count = pass;
	ev->drop_count = drop;
	bpf_ringbuf_submit(ev, 0);
}

static __always_inline __u8 port_tier(__u16 dport)
{
	struct elite_port_key pk = { .port = dport, ._pad = 0 };
	__u8 *t = bpf_map_lookup_elem(&elite_port_tier, &pk);
	if (t)
		return *t;
	return ELITE_TIER_STANDARD;
}

static __always_inline __u8 vip_tier(__u32 src_ip)
{
	struct elite_lpm_key lk = { .prefixlen = 32, .addr = src_ip };
	__u8 *t = bpf_map_lookup_elem(&elite_vip_lpm, &lk);
	if (t)
		return *t;
	return ELITE_TIER_COUNT;
}

static __always_inline __u32 tier_drop_ppm(struct elite_policy_value *val, __u8 tier)
{
	__u32 shed = val->shed_ppm;
	if (val->policy_version < ELITE_POLICY_VERSION_V2 || shed == 0)
		return 0;
	switch (tier) {
	case ELITE_TIER_CRITICAL:
		return shed / 20;
	case ELITE_TIER_STANDARD:
		return shed / 4;
	default:
		return shed;
	}
}

static __always_inline int token_consume(struct elite_policy_value *val, __u32 src_ip,
					 __u8 tier, __u64 cost)
{
	__u32 mu = val->mu_tokens_per_sec;
	if (mu == 0)
		mu = 10000;
	__u32 tier_ppm = ELITE_PPM_SCALE;
	if (tier < 4)
		tier_ppm = val->tier_refill_ppm[tier];
	if (tier_ppm == 0)
		tier_ppm = ELITE_PPM_SCALE / 2;

	__u64 refill_rate = (__u64)mu * tier_ppm / ELITE_PPM_SCALE;
	if (refill_rate == 0)
		refill_rate = 1;

	struct elite_src_key sk = { .src_ip = src_ip, .tier = tier };
	struct elite_token_bucket *b = bpf_map_lookup_elem(&elite_src_buckets, &sk);
	struct elite_token_bucket newb = { 0 };
	__u64 now = bpf_ktime_get_ns();

	if (!b) {
		newb.tokens = refill_rate;
		newb.last_refill_ns = now;
		bpf_map_update_elem(&elite_src_buckets, &sk, &newb, BPF_ANY);
		b = bpf_map_lookup_elem(&elite_src_buckets, &sk);
		if (!b)
			return 1;
	}

	__u64 elapsed = now - b->last_refill_ns;
	if (elapsed > 1000000000ULL) {
		__u64 add = (elapsed / 1000000000ULL) * refill_rate;
		b->tokens += add;
		if (b->tokens > refill_rate * 10)
			b->tokens = refill_rate * 10;
		b->last_refill_ns = now;
	}

	if (b->tokens >= cost) {
		b->tokens -= cost;
		return 1;
	}
	return 0;
}

static __always_inline int parse_ipv4_tcp(void *data, void *data_end, __u32 *src_ip,
					  __u16 *dport, __u8 *tcp_flags)
{
	struct ethhdr *eth = data;
	if ((void *)(eth + 1) > data_end)
		return -1;
	if (eth->h_proto != bpf_htons(ETH_P_IP))
		return -1;

	struct iphdr *iph = (void *)(eth + 1);
	if ((void *)(iph + 1) > data_end)
		return -1;
	if (iph->version != 4)
		return -1;
	if (iph->protocol != IPPROTO_TCP)
		return -1;

	__u32 ihl = iph->ihl * 4;
	if (ihl < sizeof(*iph))
		return -1;
	struct tcphdr *tcp = (void *)iph + ihl;
	if ((void *)(tcp + 1) > data_end)
		return -1;

	*src_ip = iph->saddr;
	*dport = bpf_ntohs(tcp->dest);
	__u8 flg = 0;
	if (tcp->syn)
		flg |= TCP_FLAG_SYN;
	*tcp_flags = flg;
	return 0;
}

SEC("xdp")
int xdp_mitigator(struct xdp_md *ctx)
{
	__u32 key = ELITE_POLICY_KEY_GLOBAL;
	struct elite_policy_value *val;
	void *data = (void *)(long)ctx->data;
	void *data_end = (void *)(long)ctx->data_end;
	__u32 src_ip = 0;
	__u16 dport = 0;
	__u8 tcp_flags = 0;
	__u8 tier = ELITE_TIER_STANDARD;
	int parsed = 0;
	__u32 syn_batch = 0;

	val = bpf_map_lookup_elem(&elite_policy, &key);
	if (!val || !val->actuate)
		return XDP_PASS;

	parsed = parse_ipv4_tcp(data, data_end, &src_ip, &dport, &tcp_flags);
	if (parsed == 0) {
		if (tcp_flags & TCP_FLAG_SYN)
			syn_batch = 1;
		tier = port_tier(dport);
		__u8 vt = vip_tier(src_ip);
		if (vt < ELITE_TIER_COUNT)
			tier = vt;

		if (val->escalate_flags & ELITE_ESC_SOURCE_BLOCK) {
			__u8 *blocked = bpf_map_lookup_elem(&elite_src_block, &src_ip);
			if (blocked) {
				xdp_bump_stat(0, 1, 0);
				maybe_emit_lambda(syn_batch, 0, 1);
				return XDP_DROP;
			}
		}

		if (val->escalate_flags & ELITE_ESC_SYN_PROXY && (tcp_flags & TCP_FLAG_SYN)) {
			if (!token_consume(val, src_ip, tier, 1)) {
				xdp_bump_stat(0, 1, 0);
				maybe_emit_lambda(syn_batch, 0, 1);
				return XDP_DROP;
			}
		}
	}

	/* v3 token-bucket path */
	if (val->policy_version >= ELITE_POLICY_VERSION_V3 && parsed == 0) {
		if (token_consume(val, src_ip, tier, 1)) {
			xdp_bump_stat(1, 0, 0);
			maybe_emit_lambda(syn_batch, 1, 0);
			return XDP_PASS;
		}
		__u32 drop_ppm = tier_drop_ppm(val, tier);
		if (drop_ppm > 0) {
			__u32 rnd = bpf_get_prandom_u32();
			if (rnd % ELITE_PPM_SCALE < drop_ppm) {
				__u32 dev_k = 0;
				__u32 *dev = bpf_map_lookup_elem(&elite_devmap, &dev_k);
				if (tier == ELITE_TIER_CRITICAL && dev && *dev > 0) {
					xdp_bump_stat(0, 0, 1);
					maybe_emit_lambda(syn_batch, 0, 0);
					return bpf_redirect_map(&elite_devmap, dev_k, 0);
				}
				if (val->redirect_ifindex > 0 && tier == ELITE_TIER_CRITICAL) {
					xdp_bump_stat(0, 0, 1);
					maybe_emit_lambda(syn_batch, 0, 0);
					return bpf_redirect(val->redirect_ifindex, 0);
				}
				xdp_bump_stat(0, 1, 0);
				maybe_emit_lambda(syn_batch, 0, 1);
				return XDP_DROP;
			}
		}
		xdp_bump_stat(1, 0, 0);
		maybe_emit_lambda(syn_batch, 1, 0);
		return XDP_PASS;
	}

	/* Graduated shed (v2) */
	if (val->policy_version >= ELITE_POLICY_VERSION_V2 && val->shed_ppm > 0) {
		__u32 rnd = bpf_get_prandom_u32();
		if (rnd % ELITE_PPM_SCALE < val->shed_ppm) {
			xdp_bump_stat(0, 1, 0);
			maybe_emit_lambda(syn_batch, 0, 1);
			return XDP_DROP;
		}
		if (val->redirect_ifindex > 0) {
			xdp_bump_stat(0, 0, 1);
			maybe_emit_lambda(syn_batch, 0, 0);
			return bpf_redirect(val->redirect_ifindex, 0);
		}
		xdp_bump_stat(1, 0, 0);
		maybe_emit_lambda(syn_batch, 1, 0);
		return XDP_PASS;
	}

	/* Legacy binary drop */
	if (val->fault &&
	    (val->cause == ELITE_CAUSE_NETWORK || val->cause == ELITE_CAUSE_MIXED)) {
		xdp_bump_stat(0, 1, 0);
		maybe_emit_lambda(syn_batch, 0, 1);
		return XDP_DROP;
	}

	xdp_bump_stat(1, 0, 0);
	maybe_emit_lambda(syn_batch, 1, 0);
	return XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";
