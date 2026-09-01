#!/usr/bin/env bash
export REAL_ONLY=1
export ELITE_SRC=/opt/elite/src
export PATH="/usr/local/bin:/root/.cargo/bin:${PATH}"
exec bash /opt/elite/src/scripts/contabo/run-linux-ebpf-challenge-proof.sh "$@"
