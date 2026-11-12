#!/usr/bin/env bash
#SBATCH --job-name=evalB-submit
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=03:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# evalB: put the CaP-Agent0 reference image into the queue (downloads ~64GB of weights)
#   sbatch --export=ALL,SUB_ID=robosuite-1 ~/jobs/evalB_submit.sh
set -euo pipefail
: "${SUB_ID:?pass SUB_ID=<submission-id>}"
hostname
cd ~/geniac_prize_2026_code
export CAPX_HF_TOKEN=$(cat ~/.cache/huggingface/token)
~/capx-venv/bin/python -m capx.cli.main evalq submit --config ~/capx-queue/queue.yaml \
    --manifest singularity/capx-submission-agent0.yaml \
    --image /scratch/$USER/capx-queue/images/capx-submission-agent0.sif \
    --submission-id "$SUB_ID"
du -sh /scratch/$USER/capx-queue/root/weights/*/*
