"""Make an evaluation-A run spec that re-runs some tasks with VIKING's task configs.

    python make_spec.py <base spec> <out spec> --output-dir <dir> --task two_arm_lift=<config.yaml> [...]

<base spec> is the spec the earlier evaluation A used: best its run directory's plan.json (the spec exactly as it ran,
absolute paths), or a spec YAML such as geniac_prize_2026_baseline/configs/eval_base.yaml.
Every setting is kept (model, servers, timeouts, seeds); only the tasks named with --task are kept, each with the
given config. Relative paths in the base spec are made absolute, so the new spec can live anywhere.
Then: geniac-baseline eval plan --spec <out spec>; bash <output_dir>/run.sh; geniac-baseline eval score <output_dir>.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

PATH_KEYS = ("capx_root", "output_dir", "chat_template", "adapter", "model_path", "molmo_path")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("base", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--task", action="append", required=True, help="task=config.yaml")
    ap.add_argument("--seeds", default=None, help="override seeds, e.g. 401-450")
    ap.add_argument("--port-offset", type=int, default=None, help="override port_offset (eval team: 1000-1900)")
    a = ap.parse_args()

    base_dir = a.base.resolve().parent
    if a.base.suffix == ".json":
        spec = json.loads(a.base.read_text())
        spec.pop("servers", None)  # plan.json adds the server command lines; not a spec key
    else:
        spec = yaml.safe_load(a.base.read_text())

    def absol(v):
        p = Path(str(v)).expanduser()
        return str(p if p.is_absolute() else (base_dir / p).resolve())

    for k in PATH_KEYS:
        if spec.get(k) and not (k in ("model_path", "molmo_path") and "/" not in str(spec[k])):
            spec[k] = absol(spec[k])
    wanted = dict(t.split("=", 1) for t in a.task)
    by_task = {t["task"]: t for t in spec["tasks"]}
    tasks = []
    for name, cfg in wanted.items():
        if name not in by_task and len(spec["tasks"]) == 1:
            by_task[name] = dict(spec["tasks"][0], task=name)
        if name not in by_task:
            raise SystemExit(f"{name} is not in {a.base}")
        t = dict(by_task[name])
        t["config"] = str(Path(cfg).expanduser().resolve())
        if a.seeds:
            t["seeds"] = [a.seeds]
        tasks.append(t)
    spec["tasks"] = tasks
    spec["output_dir"] = str(a.output_dir.expanduser().resolve())
    if a.port_offset is not None:
        spec["port_offset"] = a.port_offset
    a.out.write_text(yaml.safe_dump(spec, sort_keys=False, allow_unicode=True))
    print(f"{a.out}: {[(t['task'], t['config'], t['seeds']) for t in tasks]} -> {spec['output_dir']}")


if __name__ == "__main__":
    main()
