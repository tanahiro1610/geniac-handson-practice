#!/usr/bin/env bash
#SBATCH --job-name=dl-models
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=03:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# models for evalA (skip if /scratch/shared/models already has them)
set -euo pipefail
M=/scratch/shared/models
HF=/scratch/$USER/geniac_prize_2026_baseline/.venv/bin/hf
$HF download Qwen/Qwen3.8-27B --revision 1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0 --local-dir $M/Qwen3.8-27B
$HF download allenai/Molmo2-8B --local-dir $M/Molmo2-8B
du -sh $M/*
