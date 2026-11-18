#!/usr/bin/env bash
# Stage what the bv1api image needs (login node is fine: git clone + file copies only).
#   bash ~/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/prepare_bv1api.sh
# The image is capx-submission-bv1.sif with the operations baseline's submission overlay on top
# (geniac_prize_2026_baseline/submission/install.sh): the same APIs, skills and prompts as evaluation A.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BL=${BL:-$HOME/geniac_prize_2026_baseline}
BL_REV=${BL_REV:-646c076}   # the baseline commit the overlay was checked against (2026-11-18)
STAGE=${STAGE:-/scratch/$USER/capx-queue/bv1api-build}
BASE_SIF=${BASE_SIF:-/scratch/$USER/capx-queue/images/capx-submission-bv1.sif}

[ -f "$BASE_SIF" ] || { echo "missing $BASE_SIF (build capx-submission-bv1 first)"; exit 1; }
if [ ! -d "$BL/.git" ]; then
  git clone -q https://github.com/matsuolab/geniac_prize_2026_baseline.git "$BL"
fi
echo "baseline repo: $BL at $(git -C "$BL" rev-parse --short HEAD) (checked: $BL_REV)"
if ! git -C "$BL" merge-base --is-ancestor "$BL_REV" HEAD 2>/dev/null; then
  echo "WARNING: $BL does not contain $BL_REV; run: git -C $BL fetch && git -C $BL checkout $BL_REV"
fi

rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$BL/submission" "$STAGE/submission"
cp "$BL/patches/geniac_prize/skill-library.patch" "$STAGE/submission/"
cp "$HERE/runner-baseline-v1-api.yaml" "$STAGE/"
sed "s#@BASE_SIF@#$BASE_SIF#" "$HERE/capx-submission-bv1api.def.in" > "$STAGE/capx-submission-bv1api.def"
git -C "$BL" rev-parse HEAD > "$STAGE/submission/BASELINE_REV"
ls -l "$STAGE" "$STAGE/submission"
echo "next: sbatch $HERE/build_bv1api.sbatch"
