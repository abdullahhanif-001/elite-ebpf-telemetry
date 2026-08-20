#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note

# Version of libbpf to fetch headers from
LIBBPF_VERSION=0.5.0

# The headers we want
prefix=libbpf-"$LIBBPF_VERSION"
headers=(
    "$prefix"/src/bpf_core_read.h
    "$prefix"/src/bpf_helper_defs.h
    "$prefix"/src/bpf_helpers.h
    "$prefix"/src/bpf_tracing.h
)

# Fetch libbpf release and extract the desired headers
curl --proto "=https" --tlsv1.2 -fsSL \
    "https://github.com/libbpf/libbpf/archive/refs/tags/v${LIBBPF_VERSION}.tar.gz" \
    -o libbpf.tgz
tar -xzf libbpf.tgz --xform='s#.*/##' "${headers[@]}"
rm -f libbpf.tgz
