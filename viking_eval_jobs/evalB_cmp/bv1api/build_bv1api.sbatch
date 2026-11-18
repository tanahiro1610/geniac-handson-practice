#!/usr/bin/env bash
#SBATCH --job-name=build-bv1api
#SBATCH --partition=part-group_1a6e94
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=/home/%u/logs/%x-%j.out
# Layer the baseline overlay on capx-submission-bv1.sif (a few minutes: no download, one patch + copies).
#   sbatch ~/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/build_bv1api.sbatch
set -euo pipefail
if ! command -v singularity > /dev/null; then
    set +u   # compute-node jobs have no `module`; load lmod first
    source /opt/share/apps/lmod/lmod/init/bash
    set -u
    export MODULEPATH=/opt/share/modules/modulefiles/latest/Linux:/opt/share/modules/modulefiles/latest/Core:/opt/share/apps/lmod/lmod/modulefiles/Core
    module load singularitypro/4.1
fi
STAGE=${STAGE:-/scratch/$USER/capx-queue/bv1api-build}
OUT=${OUT:-/scratch/$USER/capx-queue/images/capx-submission-bv1api.sif}
export SINGULARITY_TMPDIR="/var/tmp/${USER}/sif-tmp"
mkdir -p "$SINGULARITY_TMPDIR"
cd "$STAGE"
singularity build --fakeroot --force "$OUT" capx-submission-bv1api.def
ls -lh "$OUT"
# What the runner will read: API per task config, and the task_map of the runner we use.
singularity exec "$OUT" bash -c 'cd /workspace/capx/env_configs/gateway && grep -A1 "^apis:" franka_*.yaml && grep -A12 "^task_map:" runner-baseline-v1-api.yaml && grep -c "def open_drawer_by_handle" /workspace/capx/capx/integrations/franka/libero_reduced_skill_library.py'
