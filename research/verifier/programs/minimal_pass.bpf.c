// SPDX-License-Identifier: GPL-2.0
/* Minimal socket program — expects verifier LOAD on capable hosts. */
#include "common.h"

char LICENSE[] SEC("license") = "GPL";

SEC("socket")
int minimal_pass(struct __sk_buff *skb)
{
	(void)skb;
	return 0;
}
