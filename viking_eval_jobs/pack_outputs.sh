#!/usr/bin/env bash
#SBATCH --job-name=pack-outputs
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# outputs (no videos) -> ~/geniac_outputs_<date>.tgz, file list -> ~/geniac_outputs_<date>.txt
set -euo pipefail
D=$(date +%Y%m%d)
OUT=$HOME/geniac_outputs_$D.tgz
LIST=$HOME/geniac_outputs_$D.txt
cd /scratch/$USER
ITEMS=()
for p in geniac_prize_2026_baseline/runs geniac_prize_2026_baseline/configs capx-queue/root/results capx-queue/root/runs logs; do
  [ -e "$p" ] && ITEMS+=("$p")
done
find "${ITEMS[@]}" -not -name '*.mp4' -not -name '*.png' -not -path '*/submission-home/*' -not -path '*/tmp-*' | sort > "$LIST"
tar czf "$OUT" --exclude='*.mp4' --exclude='.cache' --exclude='submission-home' --exclude='tmp-*' "${ITEMS[@]}"
ls -lh "$OUT"; wc -l "$LIST"
