#!/usr/bin/env bash
#SBATCH --job-name=pick-videos
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# Pick a few evalA videos per task (successes and real failures) into ~/videos_pick.tgz
#   sbatch ~/jobs/pick_videos.sh
#   sbatch --export=ALL,N=3,TASKS="spill_wipe two_arm_lift" ~/jobs/pick_videos.sh
# A failure is a seed with no taskcompleted_1 folder; its last folder is copied.
set -euo pipefail
N=${N:-2}
TASKS=${TASKS:-"cube_lifting cube_stack cube_restack spill_wipe nut_assembly two_arm_handover two_arm_lift"}
PREFIX=${PREFIX:-evalA_base}
cd /scratch/$USER/geniac_prize_2026_baseline/runs
OUT=$HOME/videos_pick
rm -rf "$OUT"; mkdir -p "$OUT"
for t in $TASKS; do
  for d in $(ls -d ${PREFIX}_${t}_*/seg_*/outputs/*/${t} 2>/dev/null); do
    seeds=$(ls -d $d/trial_* 2>/dev/null | sed -E 's#.*/trial_([0-9]+)_.*#\1#' | sort -u)
    ok=0; ng=0
    for s in $seeds; do
      last=$(ls -d $d/trial_${s}_* | tail -1)
      if ls -d $d/trial_${s}_*_taskcompleted_1 >/dev/null 2>&1; then
        [ $ok -ge $N ] && continue
        kind=ok; ok=$((ok+1)); src=$(ls -d $d/trial_${s}_*_taskcompleted_1 | tail -1)
      else
        [ $ng -ge $N ] && continue
        kind=ng; ng=$((ng+1)); src=$last
      fi
      dst=$OUT/$t/${kind}_seed${s}
      mkdir -p "$dst"
      cp $src/*.mp4 "$dst"/ 2>/dev/null || echo "no mp4 in $src"
      cp $src/summary.txt "$dst"/ 2>/dev/null || true
    done
  done
done
du -sh "$OUT"
find "$OUT" -name "*.mp4" | sort
tar czf $HOME/videos_pick.tgz -C $HOME videos_pick
ls -lh $HOME/videos_pick.tgz
