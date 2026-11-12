#!/usr/bin/env bash
#SBATCH --job-name=eval-sft
#SBATCH --partition=part-group_1a6e94
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=04:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
set -euo pipefail
# ---- sbatch --export=ALL,... で渡すもの ----
: "${NAME:?比較の名前（例 q35-4b_common7_sft_v1）}"
: "${MODEL:?Hugging Face の名前（例 Qwen/Qwen3.5-4B）}"
: "${MODEL_PATH:?ベースモデルのフォルダ}"
: "${ADAPTER:?LoRA のフォルダ}"
: "${SEEDS:?seed の範囲（例 401-402）}"
TASKS=${TASKS:-"cube_lifting cube_stack cube_restack"}
VARIANTS=${VARIANTS:-"base sft"}
OFF=${OFF:-1800}
MAXLEN=${MAXLEN:-262144}
# the ports this eval uses (vLLM 8110/8111, perception 8113-8117, Molmo 8122, plus OFF) must be free
python3 - "$OFF" <<'PY2' || { echo "FATAL: port conflict (OFF=${OFF}). Change OFF."; exit 1; }
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
PY2
B=/scratch/$USER/geniac_prize_2026_baseline
TEMPLATE=$B/runs/templates/$(basename "$MODEL_PATH").jinja
cd "$B"
export VLLM_USE_FLASHINFER_SAMPLER=0
[ -f "$TEMPLATE" ] || .venv/bin/python ~/jobs/make_chat_template.py "$MODEL_PATH" "$TEMPLATE"
for V in $VARIANTS; do
  if [ "$V" = sft ]; then AD="$ADAPTER"; LN=sft; else AD=null; LN=null; fi
  TAG=${NAME}_${V}_${SEEDS}
  SPEC=configs/sft_${TAG}.yaml
  RUN_DIR=$B/runs/sft_${TAG}
  {
    cat <<YAML
mode: eval
capx_root: ../geniac_prize_2026_code
launch_script: capx/envs/launch.py
sim_python: .venv/bin/python
serve_python: .venv-serve/bin/python
pythonpath: null
model: ${MODEL}
model_path: ${MODEL_PATH}
molmo: true
molmo_path: /scratch/shared/models/Molmo2-8B
chat_template: ${TEMPLATE}
output_dir: ../runs/sft_${TAG}
port_offset: ${OFF}
vllm_port_offset: ${OFF}
b300_workarounds: true
num_workers: null
trial_timeout_s: 2400
max_model_len: ${MAXLEN}
tensor_parallel_size: 1
qwen_gpu_util: null
molmo_gpu_util: 0.28
adapter: ${AD}
lora_name: ${LN}
code_thinking: false
tasks:
YAML
    for T in $TASKS; do
      printf '  - task: %s\n    config: capx/geniac_prize/robosuite/%s.yaml\n    seeds: ["%s"]\n' "$T" "$T" "$SEEDS"
    done
  } > "$SPEC"
  echo "===== ${V}: ${MODEL} / ${NAME} / seeds ${SEEDS} / ${TASKS} / $(hostname)"
  .venv/bin/geniac-baseline eval plan --spec "$SPEC"
  bash "$RUN_DIR/run.sh"
  .venv/bin/geniac-baseline eval score "$RUN_DIR" --json "$RUN_DIR/score.json"
  echo "Inference failed: $(grep -r 'Inference failed' "$RUN_DIR" | wc -l)"
done
echo "===== 比較"
for V in $VARIANTS; do echo "--- $V"; cat "$B/runs/sft_${NAME}_${V}_${SEEDS}/score.json"; echo; done
