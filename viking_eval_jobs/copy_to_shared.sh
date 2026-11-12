#!/usr/bin/env bash
#SBATCH --job-name=copy-shared
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# sbatch --export=ALL,SRC=<copy from>,DST=/scratch/shared/... ~/jobs/copy_to_shared.sh
set -euo pipefail
: "${SRC:?SRC}"; : "${DST:?DST}"
mkdir -p "$DST"
rsync -aL --exclude '.cache' "$SRC"/ "$DST"/
chmod -R g+rX "$DST"
ls -la "$DST" && du -sh "$DST"
