"""Write a queue config for the comparison: your ~/capx-queue/queue.yaml with the
subsets swapped for the comparison pack (Robosuite and LIBERO as two subsets) and
LIBERO added to the simulators. Everything else (root, master_seed, images) is kept,
so both models run on the same seeds.

  ~/capx-venv/bin/python make_queue_cmp.py ~/capx-queue/pack-cmp ~/capx-queue/queue-cmp.yaml
"""
import sys
from pathlib import Path

import yaml

pack, out = sys.argv[1], sys.argv[2]
base = Path.home() / "capx-queue/queue.yaml"
q = yaml.safe_load(base.read_text()) or {}
if "master_seed" not in q:
    raise SystemExit(f"{base} has no master_seed: add one (any integer) so both runs share seeds")
q["subsets"] = [
    {"name": "robosuite", "taskpack": pack, "simulators": ["robosuite"]},
    {"name": "libero", "taskpack": pack, "simulators": ["libero"]},
]
sims = q.get("simulators")
if sims is None:
    print("note: queue.yaml has no simulators section; the defaults (repo singularity/images) apply")
else:
    if "libero" not in sims:
        rs = sims["robosuite"]["image"]
        sims["libero"] = {"image": rs.replace("capx-env-robosuite", "capx-env-libero"),
                          "max_lanes": sims["robosuite"].get("max_lanes", 32)}
    for name, s in sims.items():
        img = Path(str(s.get("image", ""))).expanduser()
        if s.get("image") and not img.exists():
            print(f"WARNING: {name} image {img} does not exist yet (build it first)")
Path(out).expanduser().write_text(yaml.safe_dump(q, sort_keys=False, allow_unicode=True))
print(f"wrote {out}")
print(yaml.safe_dump({k: q[k] for k in ("root", "subsets", "simulators") if k in q}, sort_keys=False))
