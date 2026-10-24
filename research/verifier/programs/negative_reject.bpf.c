// SPDX-License-Identifier: GPL-2.0
/* Unbounded loop — kernel verifier must REJECT (no bypass claim without this oracle). */
#include "common.h"

char LICENSE[] SEC("license") = "GPL";

SEC("socket")
int negative_reject(struct __sk_buff *skb)
{
	(void)skb;
	for (;;)
		;
	return 0;
}
