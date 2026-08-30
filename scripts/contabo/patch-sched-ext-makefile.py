#!/usr/bin/env python3
"""Insert rt_guard_stress into sched_ext kselftest auto-test-targets after rt_stall."""
import pathlib
import re
import sys

p = pathlib.Path("/opt/scx-kernel-build/tools/testing/selftests/sched_ext/Makefile")
text = p.read_text()
if "rt_guard_stress" in text:
    print("Makefile already contains rt_guard_stress")
    sys.exit(0)

lines = text.splitlines()
out = []
inserted = False
for line in lines:
    out.append(line)
    if not inserted and re.search(r"\brt_stall\b", line) and line.rstrip().endswith("\\"):
        out.append("\trt_guard_stress\t\t\t\\")
        inserted = True

if not inserted:
    print("ERROR: rt_stall line not found in Makefile", file=sys.stderr)
    sys.exit(1)

p.write_text("\n".join(out) + "\n")
print("Makefile updated (rt_guard_stress added)")
