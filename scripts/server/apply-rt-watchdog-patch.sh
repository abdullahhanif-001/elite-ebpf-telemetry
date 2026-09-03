#!/usr/bin/env bash
# apply-rt-watchdog-patch.sh — Layer 2: RT-aware watchdog in kernel/sched/ext.c
set -euo pipefail

EXT_C="${1:-/opt/scx-kernel-build/kernel/sched/ext.c}"

[[ -f "${EXT_C}" ]] || { echo "FAIL missing ${EXT_C}"; exit 1; }

if grep -q 'scx_stall_caused_by_rt' "${EXT_C}"; then
  echo "PATCH_ALREADY_APPLIED"
  exit 0
fi

python3 - "${EXT_C}" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()

helper = """
static bool scx_partial_switch(void)
{
\treturn static_branch_unlikely(&__scx_switched_all);
}

/*
 * Returns true if stall is likely RT monopolization, not a BPF bug.
 * sched-ext/scx#1202
 */
static bool scx_stall_caused_by_rt(struct task_struct *p, struct rq *rq)
{
\tconst struct cpumask *mask;
\tint cpu;

\tif (p->nr_cpus_allowed == 1 &&
\t    rq->curr && rq->curr->sched_class == &rt_sched_class)
\t\treturn true;

\tif (scx_partial_switch())
\t\treturn false;

\tmask = p->cpus_ptr;
\tif (!mask)
\t\treturn false;

\trcu_read_lock();
\tfor_each_cpu(cpu, mask) {
\t\tstruct rq *rqi = cpu_rq(cpu);

\t\tif (rqi->rt.rt_nr_running == 0) {
\t\t\trcu_read_unlock();
\t\t\treturn false;
\t\t}
\t}
\trcu_read_unlock();

\treturn true;
}

"""

marker = "static bool check_rq_for_timeouts(struct rq *rq)"
if marker not in text:
    sys.exit("marker not found")
text = text.replace(marker, helper + marker, 1)

pat = re.compile(
    r"(if \(unlikely\(time_after\(jiffies,\s+last_runnable \+ scx_watchdog_timeout\)\)\) \{\s+)"
    r"(u32 dur_ms = jiffies_to_msecs\(jiffies - last_runnable\);\s+scx_exit\(sch, SCX_EXIT_ERROR_STALL, 0,)",
    re.MULTILINE,
)
repl = r"\1if (scx_stall_caused_by_rt(p, rq))\n\t\t\t\tcontinue;\n\n\t\t\t\2"
new_text, n = pat.subn(repl, text, count=1)
if n != 1:
    sys.exit(f"stall block replace failed (n={n})")
open(path, "w", encoding="utf-8").write(new_text)
print("RT_WATCHDOG_PATCH_OK")
PY

echo "done ${EXT_C}"
