#!/usr/bin/env bash
#SBATCH --job-name=evalA-libero
#SBATCH --partition=part-group_1a6e94
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=04:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# evalA for LIBERO-PRO: same conditions as the baseline's configs/eval_base_libero.yaml
# (30 tasks, layouts 50, seeds 441-450/491-500/541-550/591-600/641-650, no ensemble, .venv-libero).
#   all 30 tasks, 3 at a time:  sbatch --array=0-29%3 ~/jobs/evalA_libero.sh
#   one task, small check:      sbatch --export=ALL,TASK=libero_goal_turn_on_stove,SEEDS=441-442 ~/jobs/evalA_libero.sh
# OFF is picked automatically from the eval team's range (first one whose ports are all free).
set -euo pipefail
ALL=(
  libero_goal_bowl_on_cabinet libero_goal_bowl_on_plate libero_goal_bowl_on_stove
  libero_goal_cream_cheese_bowl libero_goal_drawer libero_goal_drawer_bowl
  libero_goal_push_plate libero_goal_turn_on_stove libero_goal_wine_on_cabinet
  libero_goal_wine_on_rack
  libero_object_alphabet_soup libero_object_bbq_sauce libero_object_butter
  libero_object_chocolate_pudding libero_object_cream_cheese libero_object_ketchup
  libero_object_milk libero_object_orange_juice libero_object_salad_dressing
  libero_object_tomato_sauce
  libero_spatial_bowl_plate libero_spatial_in_drawer libero_spatial_next_to_cookie_box
  libero_spatial_next_to_plate libero_spatial_next_to_ramekin libero_spatial_on_cabinet
  libero_spatial_on_cookie_box libero_spatial_on_ramekin libero_spatial_on_stove
  libero_spatial_table_center
)
SEEDS=${SEEDS:-441-450,491-500,541-550,591-600,641-650}
if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
  TASK=${ALL[$SLURM_ARRAY_TASK_ID]}
  sleep $(( (SLURM_ARRAY_TASK_ID % 6) * 20 ))   # stagger starts so two tasks do not grab the same OFF
else
  : "${TASK:?pass TASK=libero_goal_turn_on_stove}"
fi
B=/scratch/$USER/geniac_prize_2026_baseline
C=$B/geniac_prize_2026_code
# ---- prerequisites (tutorial 04_install.md, steps 4-5)
[ -x "$C/.venv-libero/bin/python" ] || { echo "FATAL: $C/.venv-libero is missing (tutorial 04_install.md step 4)"; exit 1; }
[ -f "$HOME/.libero/config.yaml" ] || { echo "FATAL: ~/.libero/config.yaml is missing (tutorial 04_install.md step 5)"; exit 1; }
echo "nvrtc in .venv-libero: $(ls $C/.venv-libero/lib/python3.12/site-packages 2>/dev/null | grep -i -m1 nvrtc || echo none)"
# ---- pick a free OFF (vLLM 8110/8111, perception 8113-8117, Molmo 8122, plus OFF)
OFF=$(python3 - "${OFF:-}" <<'PY'
import socket, sys
cands = [int(sys.argv[1])] if sys.argv[1] else [1000, 1100, 1200, 1300, 1400, 1500, 1600, 1800, 1900]
for off in cands:
    ok = True
    for p in [x + off for x in (8110, 8111, 8113, 8114, 8115, 8116, 8117, 8122)]:
        s = socket.socket()
        try:
            s.bind(("127.0.0.1", p))
        except OSError:
            ok = False
        finally:
            s.close()
        if not ok:
            break
    if ok:
        print(off); sys.exit(0)
sys.exit(1)
PY
) || { echo "FATAL: no free port offset"; exit 1; }
SEEDTAG=$(echo "$SEEDS" | tr ',' '_')
TAG=base_${TASK}_${SEEDTAG}
SEEDS_YAML=$(echo "$SEEDS" | sed -E 's/([0-9]+-[0-9]+)/"\1"/g; s/,/, /g')
cd "$B"
SPEC=configs/evalA_${TAG}.yaml
RUN_DIR=$B/runs/evalA_${TAG}
cat > "$SPEC" <<YAML
mode: eval
capx_root: ../geniac_prize_2026_code
launch_script: capx/envs/launch.py
sim_python: .venv-libero/bin/python
serve_python: .venv-serve/bin/python
pythonpath: null
model: Qwen/Qwen3.8-27B
model_path: /scratch/shared/models/Qwen3.8-27B
molmo: true
molmo_path: /scratch/shared/models/Molmo2-8B
chat_template: ../runs/qwen38_low_reasoning.jinja
output_dir: ../runs/evalA_${TAG}
port_offset: ${OFF}
vllm_port_offset: ${OFF}
b300_workarounds: true
num_workers: null
trial_timeout_s: 2400
max_model_len: 262144
tensor_parallel_size: 1
qwen_gpu_util: null
molmo_gpu_util: 0.28
adapter: null
lora_name: null
code_thinking: false
tasks:
  - task: ${TASK}
    config: capx/geniac_prize/libero/${TASK}.yaml
    layouts: 50
    seeds: [${SEEDS_YAML}]
YAML
echo "== ${TASK} seeds ${SEEDS} offset ${OFF} on $(hostname)"
export VLLM_USE_FLASHINFER_SAMPLER=0
.venv/bin/geniac-baseline eval plan --spec "$SPEC"
bash "$RUN_DIR/run.sh"
.venv/bin/geniac-baseline eval score "$RUN_DIR" --json "$RUN_DIR/score.json"
echo "Inference failed: $(grep -r 'Inference failed' "$RUN_DIR" | wc -l)"
