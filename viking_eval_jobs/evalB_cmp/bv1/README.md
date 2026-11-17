# baseline-v1 の評価B（CaP-Agent0・Qwen3.8-27B・BF16・max_tokens 32768）

2026-11-18 に共有された baseline-v1 の推論設定で、評価B（運営の評価キュー）を回すための材料。

| ファイル | 中身 |
| --- | --- |
| `runner-baseline-v1.yaml` | 共有された runner の設定そのまま（max_tokens 32768、9候補＋統合、16レーン） |
| `prepare_bv1.sh` | `~/geniac_prize_2026_code` に runner を置き、起動処理で量子化を環境変数から選べるようにし、`capx-submission-bv1.def` を作る（ファイルの編集だけ） |
| `submission-bv1.yaml` | BF16・KV auto・文脈 65536・思考の強さは既定（xhigh）＝ baseline-v1 の書いてあるとおり |
| `submission-bv1-low.yaml` | 上と同じで、思考の強さだけ low（運営ベースラインの収集と同じ） |

起動処理の変更は、環境変数を付けなければ運営の参照と同じ動き（fp8 / fp8）になる。

```bash
# 1. ビルドの準備（ログインノードでよい。ファイルの編集だけ）
cd ~/viking-eval && git pull -q
bash ~/viking-eval/viking_eval_jobs/evalB_cmp/bv1/prepare_bv1.sh

# 2. イメージを作る（計算ノードのジョブ。30〜60分）
cd ~/geniac_prize_2026_code
CAPX_IMAGE_DIR=/scratch/$USER/capx-queue/images sbatch -p part-group_1a6e94 singularity/build.sbatch submission-bv1

# 3. 試し流し用のパックとキュー（計算ノードで）。cube_lifting は 16 試行にして、
#    1試行に使える時間を本番（16レーン）と同じにする
srun -p part-group_1a6e94 -c 1 --mem=4G -t 00:10:00 bash -c '
cd ~/geniac_prize_2026_code
J=~/viking-eval/viking_eval_jobs/evalB_cmp; P=~/capx-venv/bin/python
$P $J/make_cmp_pack.py ~/capx-queue/pack-rs16-smoke --robosuite cube_lifting --libero --robosuite-trials 16 --seeds 401-416
$P $J/make_queue_cmp.py ~/capx-queue/pack-rs16-smoke ~/capx-queue/queue-rs16-smoke.yaml | head -1'

# 4. 試し流し（2のイメージができてから。xhigh と low を Robosuite・LIBERO-PRO で、GPU 4枚）
S=~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh; Q=$HOME/capx-queue
a1=$(sbatch --parsable --export=ALL,WHO=bv1,SUB_ID=smoke-1,CONFIG=$Q/queue-rs16-smoke.yaml $S)
a2=$(sbatch --parsable --dependency=afterany:$a1 --export=ALL,WHO=bv1low,SUB_ID=smoke-1,CONFIG=$Q/queue-rs16-smoke.yaml $S)
b1=$(sbatch --parsable --export=ALL,WHO=bv1,SUB_ID=smoke-bv1-1,CONFIG=$Q/queue-lp50-smoke.yaml $S)
b2=$(sbatch --parsable --dependency=afterany:$b1 --export=ALL,WHO=bv1low,SUB_ID=smoke-bv1-1,CONFIG=$Q/queue-lp50-smoke.yaml $S)
module load singularitypro/4.1
cd ~/geniac_prize_2026_code
W="env -i PATH=$PATH HOME=$HOME LANG=$LANG CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=180G --export=ALL"
for d in $a1 $a2; do $W --dependency=afterok:$d -t 04:00:00 --job-name=evalB-bv1-rs scripts/evalq/worker.sbatch --config $Q/queue-rs16-smoke.yaml --max-jobs 1; done
for d in $b1 $b2; do $W --dependency=afterok:$d -t 05:00:00 --job-name=evalB-bv1-lp scripts/evalq/worker.sbatch --config $Q/queue-lp50-smoke.yaml --max-jobs 1; done
```

試し流しで確かめること:
- `vllm.log` の `non-default args` に `quantization` が無く、`kv_cache_dtype` が `auto`（BF16 で動いた）
- `summary.txt` の `Code block 0` が Python のコード（思考がコードに漏れていない）
- cube_lifting の成功数、`trials_finished`、時間切れの有無（16試行・16レーン＝本番と同じ1試行あたりの時間）
- `vllm.log` に HTTP 400（文脈長 65536 の超過）が無い
- LIBERO-PRO の30タスクの env が作れた
