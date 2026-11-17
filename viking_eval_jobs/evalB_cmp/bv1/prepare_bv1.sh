#!/usr/bin/env bash
# Prepare ~/geniac_prize_2026_code to build the baseline-v1 submission image (capx-submission-bv1.sif).
# Only file edits (safe on the login node); the build itself is a Slurm job (see README).
#  - env_configs/gateway/runner-baseline-v1.yaml  : the shared baseline-v1 runner (max_tokens 32768)
#  - singularity/agent0-entrypoint.sh             : vLLM quantization / KV-cache dtype from the environment
#        CAPX_QUANTIZATION (default fp8; "none" = BF16 weights, no on-the-fly quantization)
#        CAPX_KV_CACHE_DTYPE (default fp8; "auto" = the model dtype)
#    Defaults keep the reference behaviour, so the reference image built from this tree is unchanged.
#  - singularity/capx-submission-bv1.def          : a copy of the agent0 def, so the build writes a new
#    .sif and leaves capx-submission-agent0.sif alone
# The build stages git-tracked files only, so the new files are `git add`-ed (not committed).
set -euo pipefail
C=${C:-$HOME/geniac_prize_2026_code}
H=$(cd "$(dirname "$0")" && pwd)
cd "$C"

cp "$H/runner-baseline-v1.yaml" env_configs/gateway/runner-baseline-v1.yaml

E=singularity/agent0-entrypoint.sh
if grep -q 'QUANT_FLAGS' "$E"; then
    echo "entrypoint already patched"
else
    python3 - "$E" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "    --quantization fp8 \\\n    --kv-cache-dtype fp8 \\\n"
assert t.count(old) == 1, "entrypoint is not the version this patch expects"
t = t.replace(old, "    ${QUANT_FLAGS} \\\n")
anchor = 'SERVE_EXTRA_ARGS="${CAPX_SERVE_EXTRA_ARGS:---attention-backend TRITON_ATTN}"\n'
assert t.count(anchor) == 1
t = t.replace(anchor, anchor + '''# VIKING: weights / KV-cache precision from the environment (defaults = the reference: fp8 / fp8).
QUANT_FLAGS=""
[ "${CAPX_QUANTIZATION:-fp8}" = "none" ] || QUANT_FLAGS="--quantization ${CAPX_QUANTIZATION:-fp8}"
QUANT_FLAGS="${QUANT_FLAGS} --kv-cache-dtype ${CAPX_KV_CACHE_DTYPE:-fp8}"
''')
open(p, "w").write(t)
PY
    echo "entrypoint patched"
fi
bash -n "$E"

cp singularity/capx-submission-agent0.def singularity/capx-submission-bv1.def
git add env_configs/gateway/runner-baseline-v1.yaml singularity/capx-submission-bv1.def
git status --short
grep -n -A3 'VIKING: weights' "$E"
