"""Summarise evaluation-queue runs: result, time, per-task successes, and whether the code ran.

  ~/capx-venv/bin/python check_runs.py /scratch/$USER/capx-queue/root-pack-rs16-smoke [more roots...]

For every result in <root>/results and its run in <root>/runs it prints:
  status / error, budget used, trials finished, successes per task (from the gateway),
  vLLM: HTTP 400 count (context overflow etc.),
  code: how many saved code blocks (trial folders' code.py) are valid Python -- prose leaking
        out of the thinking shows up as "not python",
  env: error lines in the simulator logs (a LIBERO-PRO suite that does not exist shows here).
"""
import collections
import json
import re
import sys
from pathlib import Path

for root in map(Path, sys.argv[1:]):
    for res in sorted((root / "results").glob("*.json")):
        d = json.loads(res.read_text())
        name = res.stem
        print(f"======== {name}")
        print(f"status={d.get('status')} error={d.get('error_code')}")
        run_id = d.get("run_id") or name
        for sub, v in (d.get("subsets") or {}).items():
            lb = v.get("leaderboard") or {}
            print(f"[{sub}] budget_used={v.get('budget_used_s')}s duration={v.get('duration_s', 0):.0f}s "
                  f"finished={v.get('trials_finished')}/{lb.get('trials')} success_rate={lb.get('overall_success_rate')}")
            for t, tv in sorted((lb.get("tasks") or {}).items()):
                print(f"   {t:40s} {tv.get('successes')}/{tv.get('trials')}")
        runs = [p for p in (root / "runs").glob(name.split("__")[0] + "__" + name.split("__")[1] + "__*") if p.is_dir()]
        for run in runs:
            for subdir in sorted(p for p in run.iterdir() if p.is_dir()):
                out = subdir / "submission-out"
                vllm = out / "logs" / "vllm.log"
                if vllm.exists():
                    txt = vllm.read_text(errors="replace")
                    n400 = len(re.findall(r'" 400', txt))
                    nctx = txt.count("maximum context length")
                    print(f"   vllm: HTTP400={n400} context_overflow={nctx}")
                ok = bad = 0
                bad_tasks = collections.Counter()
                for code in out.glob("*/trial_*/code.py"):
                    try:
                        compile(code.read_text(errors="replace"), str(code), "exec")
                        ok += 1
                    except SyntaxError:
                        bad += 1
                        bad_tasks[code.parent.parent.name] += 1
                print(f"   code: python={ok} not_python={bad}" + (f" {dict(bad_tasks)}" if bad else ""))
                errs = collections.Counter()
                for log in subdir.glob("env-*.log"):
                    for line in log.read_text(errors="replace").splitlines():
                        if re.search(r"KeyError|not found|bddl|Traceback|Error:", line):
                            errs[line.strip()[:120]] += 1
                for line, n in errs.most_common(5):
                    print(f"   env x{n}: {line}")
