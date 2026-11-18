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
#   baseline-v1 + evaluation A's APIs: WHO=bv1api (Robosuite), WHO=bv1apilib (LIBERO, no ensemble)
#   smoke test:              add CONFIG=$HOME/capx-queue/queue-cmp-smoke.yaml
set -euo pipefail
: "${WHO:?WHO=q36 or q38}"; : "${SUB_ID:?SUB_ID=<new id>}"
CONFIG=${CONFIG:-$HOME/capx-queue/queue-cmp.yaml}
C=~/geniac_prize_2026_code
IMG=/scratch/$USER/capx-queue/images/capx-submission-agent0.sif
case $WHO in
  bv1) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/bv1/submission-bv1.yaml
       IMG=/scratch/$USER/capx-queue/images/capx-submission-bv1.sif ;;
  bv1low) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/bv1/submission-bv1-low.yaml
       IMG=/scratch/$USER/capx-queue/images/capx-submission-bv1.sif ;;
  bv1lowlc) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/bv1/submission-bv1-low-ctx131k.yaml
       IMG=/scratch/$USER/capx-queue/images/capx-submission-bv1.sif ;;
  bv1api) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/submission-bv1api.yaml
       IMG=/scratch/$USER/capx-queue/images/capx-submission-bv1api.sif ;;
  bv1apilib) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/submission-bv1api-libero.yaml
       IMG=/scratch/$USER/capx-queue/images/capx-submission-bv1api.sif ;;
  q36) MANIFEST=$C/singularity/capx-submission-agent0.yaml ;;
  q38) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38.yaml ;;
  q38low) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38-low.yaml ;;
  q38nt) MANIFEST=$HOME/viking-eval/viking_eval_jobs/evalB_cmp/submission-qwen38-nothink.yaml ;;
  *) echo "WHO must be bv1, bv1low, bv1lowlc, bv1api, bv1apilib, q36, q38, q38nt or q38low"; exit 1 ;;
esac
cd $C
export CAPX_HF_TOKEN=$(cat ~/.cache/huggingface/token)
~/capx-venv/bin/python -m capx.cli.main evalq submit --config "$CONFIG" \
    --manifest "$MANIFEST" \
    --image "$IMG" \
    --submission-id "$SUB_ID"
~/capx-venv/bin/python -m capx.cli.main evalq status --config "$CONFIG"
