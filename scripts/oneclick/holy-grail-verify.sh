#!/usr/bin/env bash
# Back-compat wrapper — use zero-buffer-root-verify.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zero-buffer-root-verify.sh" "$@"
