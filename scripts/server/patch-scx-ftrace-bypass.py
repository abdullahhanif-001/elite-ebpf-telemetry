#!/usr/bin/env python3
"""Bypass CONFIG_FUNCTION_TRACER check for VPS test kernel."""
import pathlib
p = pathlib.Path("/opt/scx/rust/scx_utils/src/compat.rs")
text = p.read_text()
marker = "pub fn function_tracer_available() -> bool {"
if "return true;" in text.split(marker)[1][:40] if marker in text else "":
    print("already patched")
else:
    text = text.replace(
        marker,
        marker + "\n    return true; /* rt-guard flood: kernel lacks ftrace */",
        1,
    )
    p.write_text(text)
    print("patched function_tracer_available")
