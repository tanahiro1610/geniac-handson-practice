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
# Each seed's videos sit in the folder of its final state; ok = sandboxrc_0 and taskcompleted_1 there.
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
      # videos are written once per seed, into the folder of its final state (the one scored)
      src=""
      for x in $d/trial_${s}_*; do [ -f "$x/video_combined.mp4" ] && src=$x; done
      if [ -z "$src" ]; then echo "no video for $t seed $s"; continue; fi
      case "$src" in
        *sandboxrc_0_*taskcompleted_1) [ $ok -ge $N ] && continue; kind=ok; ok=$((ok+1));;
        *) [ $ng -ge $N ] && continue; kind=ng; ng=$((ng+1));;
      esac
      dst=$OUT/$t/${kind}_seed${s}
      mkdir -p "$dst"
      cp $src/*.mp4 "$dst"/
      cp $src/summary.txt "$dst"/ 2>/dev/null || true
      echo "$src" > "$dst"/source.txt
    done
  done
done
du -sh "$OUT"
find "$OUT" -name "*.mp4" | sort
tar czf $HOME/videos_pick.tgz -C $HOME videos_pick
ls -lh $HOME/videos_pick.tgz
