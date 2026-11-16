"""Write a task pack for comparing two models on evalB (the organizer's eval queue).

Copies the tasks from taskpacks/original, sets how many trials each gets, and drops
the fixed seeds so the gateway draws them from the queue's master_seed: two runs on
the same queue config get the same seeds, so the comparison is paired.

  ~/capx-venv/bin/python make_cmp_pack.py ~/capx-queue/pack-cmp
  ~/capx-venv/bin/python make_cmp_pack.py ~/capx-queue/pack-cmp-smoke --robosuite cube_lifting \
      --libero libero_goal_7 --robosuite-trials 2 --libero-trials 2
"""
import argparse
import copy
from pathlib import Path

import yaml

ROBOSUITE = ["cube_lifting", "cube_stack", "cube_restack", "nut_assembly", "spill_wipe",
             "two_arm_lift", "two_arm_handover"]
LIBERO = [f"libero_{s}_{i}" for s in ("goal", "object", "spatial") for i in range(10)]

ap = argparse.ArgumentParser()
ap.add_argument("out", help="directory to write pack.yaml into (its name becomes the pack id)")
ap.add_argument("--original", default=str(Path.home() / "geniac_prize_2026_code/taskpacks/original/pack.yaml"))
ap.add_argument("--robosuite", nargs="*", default=ROBOSUITE)
ap.add_argument("--libero", nargs="*", default=LIBERO)
ap.add_argument("--robosuite-trials", type=int, default=20)
ap.add_argument("--libero-trials", type=int, default=10)
a = ap.parse_args()

orig = yaml.safe_load(open(a.original))
by_id = {t["task_id"]: t for t in orig["tasks"]}
missing = [t for t in a.robosuite + a.libero if t not in by_id]
if missing:
    raise SystemExit(f"not in {a.original}: {missing}")

tasks = []
for tid, n in [(t, a.robosuite_trials) for t in a.robosuite] + [(t, a.libero_trials) for t in a.libero]:
    t = copy.deepcopy(by_id[tid])
    t["n_trials"] = n
    t.pop("seed_policy", None)  # default: random, derived from the queue's master_seed
    tasks.append(t)

out = Path(a.out).expanduser()
out.mkdir(parents=True, exist_ok=True)
pack = {"pack_id": out.name, "version": "viking-1", "visibility": "public",
        "limits": dict(orig["limits"]), "tasks": tasks}
(out / "pack.yaml").write_text(yaml.safe_dump(pack, sort_keys=False, allow_unicode=True))
n_rs = len(a.robosuite) * a.robosuite_trials
n_lb = len(a.libero) * a.libero_trials
print(f"{out/'pack.yaml'}: robosuite {len(a.robosuite)}x{a.robosuite_trials}={n_rs}, "
      f"libero {len(a.libero)}x{a.libero_trials}={n_lb}, budget {(n_rs+n_lb)*orig['limits']['trial_time_s']/3600:.1f} h")
