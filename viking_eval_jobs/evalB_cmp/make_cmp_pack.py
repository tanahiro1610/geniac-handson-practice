"""Write a task pack for comparing two models on evalB (the organizer's eval queue).

Copies the tasks from taskpacks/original, sets how many trials each gets, and drops
either fixes the seeds (--seeds 401-450: the same seeds evalA used) or drops them so the
gateway draws them from the queue's master_seed. Either way two runs on the same pack and
queue config get the same seeds, so the comparison is paired.

  ~/capx-venv/bin/python make_cmp_pack.py ~/capx-queue/pack-rs50 --libero --robosuite-trials 50 --seeds 401-450
  ~/capx-venv/bin/python make_cmp_pack.py ~/capx-queue/pack-lp50 --robosuite --libero-pro --libero-trials 50
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

# evalA's LIBERO-PRO tasks (operations baseline configs/capx/geniac_prize/libero/*.yaml):
# name -> (original pack task it perturbs, LIBERO-PRO suite). Same task_id and instruction
# as the original; the suite swaps object positions (swap) or adds a mug (with_mug).
PRO_SUITE = {"goal": "libero_goal_with_mug", "object": "libero_object_swap", "spatial": "libero_spatial_swap"}
PRO_NAMES = {
    "goal": ["drawer", "bowl_on_stove", "wine_on_cabinet", "drawer_bowl", "bowl_on_cabinet",
             "push_plate", "cream_cheese_bowl", "turn_on_stove", "bowl_on_plate", "wine_on_rack"],
    "object": ["alphabet_soup", "cream_cheese", "salad_dressing", "bbq_sauce", "ketchup",
               "tomato_sauce", "butter", "milk", "chocolate_pudding", "orange_juice"],
    "spatial": ["bowl_plate", "next_to_ramekin", "table_center", "on_cookie_box", "in_drawer",
                "on_ramekin", "next_to_cookie_box", "on_stove", "next_to_plate", "on_cabinet"],
}
# evalA's LIBERO seeds: layouts 40-49 (init state (seed-1) % 50), five rounds
EVALA_LIBERO_SEEDS = "441-450,491-500,541-550,591-600,641-650"

ap = argparse.ArgumentParser()
ap.add_argument("out", help="directory to write pack.yaml into (its name becomes the pack id)")
ap.add_argument("--original", default=str(Path.home() / "geniac_prize_2026_code/taskpacks/original/pack.yaml"))
ap.add_argument("--robosuite", nargs="*", default=ROBOSUITE)
ap.add_argument("--libero", nargs="*", default=LIBERO)
ap.add_argument("--robosuite-trials", type=int, default=20)
ap.add_argument("--libero-trials", type=int, default=10)
ap.add_argument("--libero-pro", action="store_true",
                help="use evalA's 30 LIBERO-PRO tasks (goal_with_mug, object_swap, spatial_swap) instead of --libero")
ap.add_argument("--libero-seeds", default=EVALA_LIBERO_SEEDS,
                help="fixed seeds for the LIBERO-PRO tasks (default: evalA's 50; the first n are used)")
ap.add_argument("--libero-steplimit", type=int, default=0,
                help="override the LIBERO trial_steplimit (pack default 8000; evalA used max_steps 4000)")
ap.add_argument("--seeds", default="", help="fixed seeds for every task, e.g. 401-450 (trial i uses the i-th); "
                "omit for random seeds from the queue's master_seed")
a = ap.parse_args()

def parse_seeds(s):
    out = []
    for part in filter(None, s.split(",")):
        lo, _, hi = part.partition("-")
        out += list(range(int(lo), int(hi or lo) + 1))
    return out

seeds = parse_seeds(a.seeds)

orig = yaml.safe_load(open(a.original))
by_id = {t["task_id"]: t for t in orig["tasks"]}
if a.libero_pro:
    a.libero = []
missing = [t for t in a.robosuite + a.libero if t not in by_id]
if missing:
    raise SystemExit(f"not in {a.original}: {missing}")

tasks = []
for tid, n in [(t, a.robosuite_trials) for t in a.robosuite] + [(t, a.libero_trials) for t in a.libero]:
    t = copy.deepcopy(by_id[tid])
    t["n_trials"] = n
    if seeds:
        if len(seeds) < n:
            raise SystemExit(f"{tid}: {n} trials but only {len(seeds)} seeds (they would repeat)")
        t["seed_policy"] = {"mode": "fixed", "seeds": seeds[:n]}
    else:
        t.pop("seed_policy", None)  # default: random, derived from the queue's master_seed
    tasks.append(t)

if a.libero_pro:
    lseeds = parse_seeds(a.libero_seeds)
    if len(lseeds) < a.libero_trials:
        raise SystemExit(f"--libero-trials {a.libero_trials} but only {len(lseeds)} --libero-seeds")
    for group, names in PRO_NAMES.items():
        for i, name in enumerate(names):
            t = copy.deepcopy(by_id[f"libero_{group}_{i}"])
            t["task_id"] = f"libero_{group}_{name}"
            t["env_kwargs"] = {**t.get("env_kwargs", {}), "suite_name": PRO_SUITE[group]}
            t["n_trials"] = a.libero_trials
            t["seed_policy"] = {"mode": "fixed", "seeds": lseeds[:a.libero_trials]}
            if a.libero_steplimit:
                t["trial_steplimit"] = a.libero_steplimit
            tasks.append(t)
elif a.libero_steplimit:
    for t in tasks:
        if t["simulator"] == "libero":
            t["trial_steplimit"] = a.libero_steplimit

out = Path(a.out).expanduser()
out.mkdir(parents=True, exist_ok=True)
pack = {"pack_id": out.name, "version": "viking-1", "visibility": "public",
        "limits": dict(orig["limits"]), "tasks": tasks}
(out / "pack.yaml").write_text(yaml.safe_dump(pack, sort_keys=False, allow_unicode=True))
n_rs = len(a.robosuite) * a.robosuite_trials
n_lb = sum(t["n_trials"] for t in tasks if t["simulator"] == "libero")
print(f"{out/'pack.yaml'}: robosuite {len(a.robosuite)}x{a.robosuite_trials}={n_rs}, "
      f"libero {'LIBERO-PRO 30' if a.libero_pro else len(a.libero)}x{a.libero_trials}={n_lb}, seeds {a.seeds or 'random'}{' / libero ' + a.libero_seeds if a.libero_pro else ''}, budget {(n_rs+n_lb)*orig['limits']['trial_time_s']/3600:.1f} h")
