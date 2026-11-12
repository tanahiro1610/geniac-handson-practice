#!/usr/bin/env bash
#SBATCH --job-name=evalA
#SBATCH --partition=part-group_1a6e94
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=256G
#SBATCH --time=08:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# 評価A（ベースラインの評価、Qwen3.8-27B 学習前）
#   全タスク:   sbatch --array=0-6%1 ~/jobs/evalA.sh
#   1タスクだけ: sbatch --array=0 ~/jobs/evalA.sh   (0=cube_lifting ... 6=two_arm_handover)
#   manual:    sbatch --export=ALL,TASK=cube_lifting,OFF=1700 ~/jobs/evalA.sh
set -euo pipefail
ALL=(cube_lifting cube_stack cube_restack nut_assembly spill_wipe two_arm_lift two_arm_handover)
SEEDS=${SEEDS:-401-450}
if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
  TASK=${ALL[$SLURM_ARRAY_TASK_ID]}; OFF=$((1000 + 100 * SLURM_ARRAY_TASK_ID))
else
  : "${TASK:?pass TASK=cube_lifting}"; OFF=${OFF:-1700}
fi
TAG=${TAG:-base}_${TASK}_${SEEDS}
# the ports this eval uses (vLLM 8110/8111, perception 8113-8117, Molmo 8122, plus OFF) must be free
python3 - "$OFF" <<'PY' || { echo "FATAL: port conflict (OFF=${OFF}). Change OFF."; exit 1; }
import socket, sys
off = int(sys.argv[1]); busy = []
for p in [x + off for x in (8110, 8111, 8113, 8114, 8115, 8116, 8117, 8122)]:
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", p))
    except OSError:
        busy.append(p)
    finally:
        s.close()
print("busy ports:", busy if busy else "none")
sys.exit(1 if busy else 0)
PY
B=/scratch/$USER/geniac_prize_2026_baseline
cd "$B"
SPEC=configs/evalA_${TAG}.yaml
RUN_DIR=$B/runs/evalA_${TAG}
cat > "$SPEC" <<YAML
mode: eval
capx_root: ../geniac_prize_2026_code
launch_script: capx/envs/launch.py
sim_python: .venv/bin/python
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
    config: capx/geniac_prize/robosuite/${TASK}.yaml
    seeds: ["${SEEDS}"]
YAML
echo "== ${TASK} seeds ${SEEDS} offset ${OFF} on $(hostname)"
export VLLM_USE_FLASHINFER_SAMPLER=0
.venv/bin/geniac-baseline eval plan --spec "$SPEC"
bash "$RUN_DIR/run.sh"
.venv/bin/geniac-baseline eval score "$RUN_DIR" --json "$RUN_DIR/score.json"
echo "Inference failed: $(grep -r 'Inference failed' "$RUN_DIR" | wc -l)"
