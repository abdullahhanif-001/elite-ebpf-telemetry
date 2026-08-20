/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
// +build ignore

#include "vmlinux.h"
#include "bpf_helpers.h"
#include "bpf_core_read.h"
#include "bpf_tracing.h"
#include "inspector.h"

#define AF_INET 2
#define CONNECT_LAT_1MS   1
#define CONNECT_LAT_10MS  2
#define CONNECT_LAT_100MS 4

struct insp_connect_event_t {
	u64 ts_ns;
	u32 pid;
	u32 netns;
	u32 daddr;
	u16 dport;
	u16 pad;
	u64 latency_ns;
	u8 comm[TASK_COMM_LEN];
};

struct insp_connect_metric_t {
	u64 connect_total;
	u64 lat_1ms;
	u64 lat_10ms;
	u64 lat_100ms;
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 8192);
	__type(key, u64);
	__type(value, u64);
} insp_connect_start SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 256);
	__type(key, u32);
	__type(value, struct insp_connect_metric_t);
} insp_connect_metrics SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} insp_connect_events SEC(".maps");

static __always_inline u32 get_netns(void)
{
	struct task_struct *task = (void *)bpf_get_current_task();
	u32 netns = 0;

	if (!task)
		return 0;

	struct nsproxy *nsproxy;
	bpf_core_read(&nsproxy, sizeof(nsproxy), &task->nsproxy);
	if (!nsproxy)
		return 0;

	struct net *net;
	bpf_core_read(&net, sizeof(net), &nsproxy->net_ns);
	if (!net)
		return 0;

	bpf_core_read(&netns, sizeof(netns), &net->ns.inum);
	return netns;
}

static __always_inline void record_latency(u32 netns, u64 latency_ns)
{
	struct insp_connect_metric_t *mtr, zero = {};
	u64 *ts;

	mtr = bpf_map_lookup_elem(&insp_connect_metrics, &netns);
	if (!mtr) {
		bpf_map_update_elem(&insp_connect_metrics, &netns, &zero, BPF_ANY);
		mtr = bpf_map_lookup_elem(&insp_connect_metrics, &netns);
		if (!mtr)
			return;
	}

	__sync_fetch_and_add(&mtr->connect_total, 1);
	if (latency_ns >= 100000000ULL)
		__sync_fetch_and_add(&mtr->lat_100ms, 1);
	else if (latency_ns >= 10000000ULL)
		__sync_fetch_and_add(&mtr->lat_10ms, 1);
	else if (latency_ns >= 1000000ULL)
		__sync_fetch_and_add(&mtr->lat_1ms, 1);
}

SEC("tracepoint/syscalls/sys_enter_connect")
int trace_sys_enter_connect(struct trace_event_raw_sys_enter *ctx)
{
	u64 pid_tgid = bpf_get_current_pid_tgid();
	u64 ts = bpf_ktime_get_ns();

	bpf_map_update_elem(&insp_connect_start, &pid_tgid, &ts, BPF_ANY);
	return 0;
}

SEC("tracepoint/syscalls/sys_exit_connect")
int trace_sys_exit_connect(struct trace_event_raw_sys_exit *ctx)
{
	u64 pid_tgid = bpf_get_current_pid_tgid();
	u64 *start_ts = bpf_map_lookup_elem(&insp_connect_start, &pid_tgid);
	long ret = ctx->ret;

	if (!start_ts)
		return 0;

	bpf_map_delete_elem(&insp_connect_start, &pid_tgid);

	if (ret != 0)
		return 0;

	u64 latency_ns = bpf_ktime_get_ns() - *start_ts;
	u32 netns = get_netns();

	record_latency(netns, latency_ns);

	struct insp_connect_event_t *event =
		bpf_ringbuf_reserve(&insp_connect_events, sizeof(*event), 0);
	if (!event)
		return 0;

	event->ts_ns = bpf_ktime_get_ns();
	event->pid = pid_tgid >> 32;
	event->netns = netns;
	event->daddr = 0;
	event->dport = 0;
	event->latency_ns = latency_ns;
	bpf_get_current_comm(&event->comm, sizeof(event->comm));

	bpf_ringbuf_submit(event, 0);
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
