#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import time
import urllib.request

p = Path("/opt/elite/config/config.yaml")
t = p.read_text()
t2 = re.sub(
    r'\n\s*-\s*url:\s*"http://127\.0\.0\.1:9435/metrics"\n\s*series:\s*\[[^\]]*\]\n?',
    "\n",
    t,
)
p.write_text(t2)
print("changed", t != t2)
subprocess.check_call(["systemctl", "restart", "elite-agent"])
time.sleep(10)
body = urllib.request.urlopen("http://127.0.0.1:9102/metrics", timeout=5).read().decode()
print("elite_count", body.count("elite_"))
print("predict", "elite_predict_" in body)
print("METRICS_OK" if "elite_predict_" in body else "METRICS_FAIL")
