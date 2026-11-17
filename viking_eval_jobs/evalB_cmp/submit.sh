#!/usr/bin/env bash
#SBATCH --job-name=evalB-cmp-submit
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=03:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# Put one submission into the comparison queue (downloads its weights first, ~60GB).
#   reference (Qwen3.6-27B): sbatch --export=ALL,WHO=q36,SUB_ID=cmp-1 submit.sh
#   Qwen3.8-27B:             sbatch --export=ALL,WHO=q38,SUB_ID=cmp-1 submit.sh
#   Qwen3.8-27B, thinking at effort low: WHO=q38low
#   Qwen3.8-27B, no thinking: sbatch --export=ALL,WHO=q38nt,SUB_ID=cmp-1 submit.sh
#   smoke test:              add CONFIG=$HOME/capx-queue/queue-cmp-smoke.yaml
set -euo pipefail
: "${WHO:?WHO=q36 or q38}"; : "${SUB_ID:?SUB_ID=<new id>}"
CONFIG=${CONFIG:-$HOME/capx-queue/queue-cmp.yaml}
C=~/geniac_prize_2026_code
case $WHO in
  q36) MANIFEST=$C/singularity/capx-submission-agent0.yaml ;;
  q38) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38.yaml ;;
  q38low) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38-low.yaml ;;
  q38nt) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38-nothink.yaml ;;
  *) echo "WHO must be q36, q38, q38nt or q38low"; exit 1 ;;
esac
cd $C
export CAPX_HF_TOKEN=$(cat ~/.cache/huggingface/token)
~/capx-venv/bin/python -m capx.cli.main evalq submit --config "$CONFIG" \
    --manifest "$MANIFEST" \
    --image /scratch/$USER/capx-queue/images/capx-submission-agent0.sif \
    --submission-id "$SUB_ID"
~/capx-venv/bin/python -m capx.cli.main evalq status --config "$CONFIG"
