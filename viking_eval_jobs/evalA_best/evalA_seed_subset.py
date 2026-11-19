"""Evaluation A successes per task, counting only some seeds (to compare with an evaluation B run on those seeds).

  cd <geniac_prize_2026_baseline>
  .venv/bin/python ~/viking-eval/viking_eval_jobs/evalA_best/evalA_seed_subset.py --seeds 441-450 runs/<evalA LIBERO run dir> [...]

Uses the baseline's own scorer (geniac_baseline.eval.score): end-of-trial saves only, success = task completed and
the code ran. A planned seed with no end-of-trial save counts as a failure and is listed as missing.
"""

import argparse
import collections
from pathlib import Path

from geniac_baseline.eval.score import expected_seeds, find_trials, score_trial


def seed_set(text: str) -> set[int]:
    out: set[int] = set()
    for part in text.split(","):
        a, _, b = part.partition("-")
        out |= set(range(int(a), int(b or a) + 1))
    return out


ap = argparse.ArgumentParser()
ap.add_argument("--seeds", required=True)
ap.add_argument("runs", nargs="+", type=Path)
a = ap.parse_args()
want = seed_set(a.seeds)

succ: dict[str, int] = collections.Counter()
seen: dict[str, set[int]] = collections.defaultdict(set)
planned: dict[str, set[int]] = collections.defaultdict(set)
for run in a.runs:
    for task, seeds in expected_seeds(run).items():
        planned[task] |= seeds & want
    folders, _ = find_trials(run)
    for d in folders:
        t = score_trial(d)
        if t["seed"] in want:
            task = d.parent.name
            seen[task].add(t["seed"])
            succ[task] += int(t["success"])

tot_s = tot_n = 0
for task in sorted(set(planned) | set(seen)):
    n = len(planned[task] | seen[task])
    miss = sorted(planned[task] - seen[task])
    tot_s += succ[task]
    tot_n += n
    print(f"{task:45s} {succ[task]}/{n}" + (f"  missing={miss}" if miss else ""))
print(f"TOTAL seeds {a.seeds}: {tot_s}/{tot_n}")
