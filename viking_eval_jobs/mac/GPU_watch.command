#!/bin/bash
# Double-click this in Finder: it updates itself from GitHub and opens the GPU dashboard.
# Close the Terminal window (or press Ctrl+C) to stop.
cd "$(dirname "$0")/../.." || exit 1
git pull -q 2>/dev/null || echo "(could not update; using the copy you have)"
exec bash viking_eval_jobs/mac/gpu_watch.sh
