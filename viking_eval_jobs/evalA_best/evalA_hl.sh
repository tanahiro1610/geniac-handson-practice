#!/usr/bin/env bash
#SBATCH --job-name=evalA-hl
#SBATCH --partition=part-group_1a6e94
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=96G
#SBATCH --time=16:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# 評価A を、タスクの設定ファイル（API・プロンプト）だけ替えて回す。中身は ~/jobs/evalA.sh と同じ
# （spec の値・ポート確認・plan → run → score）。違いは CONFIG を渡せることと、TAG・OFF・時間の既定値。
#   two_arm_lift を高レベル API で: sbatch ~/viking-eval/viking_eval_jobs/evalA_best/evalA_hl.sh
#   ほかのタスク・設定:           sbatch --export=ALL,TASK=two_arm_handover,CONFIG=<yaml>,TAG=hl,OFF=1900 ...
# 前の評価A の two_arm_lift は 8 時間で終わらず 434-450 を回し直したので、時間は 16 時間にしてある。
# CPU・メモリは前の評価A の実測から（平均 0.5〜1.4 コア、最大メモリ 59G = handover、two_arm_lift 49G）。
set -euo pipefail
TASK=${TASK:-two_arm_lift}
CONFIG=${CONFIG:-$HOME/viking-eval/viking_eval_jobs/evalA_best/two_arm_lift_hl.yaml}
SEEDS=${SEEDS:-401-450}
OFF=${OFF:-1900}
TAG=${TAG:-hl}_${TASK}_${SEEDS}
[ -f "$CONFIG" ] || { echo "FATAL: no config $CONFIG"; exit 1; }
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
    config: ${CONFIG}
    seeds: ["${SEEDS}"]
YAML
echo "== ${TASK} seeds ${SEEDS} offset ${OFF} config ${CONFIG} on $(hostname)"
grep -A1 "^    apis:\|^  apis:\|apis:" "$CONFIG" | head -3
export VLLM_USE_FLASHINFER_SAMPLER=0
.venv/bin/geniac-baseline eval plan --spec "$SPEC"
bash "$RUN_DIR/run.sh"
.venv/bin/geniac-baseline eval score "$RUN_DIR" --json "$RUN_DIR/score.json"
echo "Inference failed: $(grep -r 'Inference failed' "$RUN_DIR" | wc -l)"
