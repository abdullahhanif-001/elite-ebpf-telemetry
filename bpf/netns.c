/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
#include <bpf_helpers.h>

SEC("tracepoint/task/newtask")
int netns(void)
{
	return 0;
}
