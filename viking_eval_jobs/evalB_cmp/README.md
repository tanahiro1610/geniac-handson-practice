# 評価B：CaP-Agent0 のモデル比較（Qwen3.6-27B と Qwen3.8-27B）

運営の評価キュー（評価B）で、CaP-Agent0 の参照実装のモデルだけを差し替えて比べます。
イメージ・ランナー・アンサンブル（オン）・知覚は同じで、違うのはモデルだけです。

| 項目 | 値 |
| --- | --- |
| Robosuite | 7タスク × 20試行 = 140 |
| LIBERO | 元の LIBERO の goal・object・spatial 各10タスク（評価Aの LIBERO-PRO の元タスク） × 10試行 = 300 |
| seed | ランダム。キュー設定の `master_seed` から決まるので、2つのモデルは同じ seed で回る |
| 1試行のステップ上限 | 公開パックと同じ（LIBERO 8000、Robosuite はタスクごと） |
| 持ち時間 | 440試行 × 300秒 = 36.7時間（上限）。参照実装の実績（1試行 約2.4分）から、実際は1モデル 約18時間 |
| GPU | 1モデルに1枚。2つを同時に回す |

## 手順（クラスタで）

0. このリポジトリを置く（初回だけ）

```bash
git clone -b eval-jobs --depth 1 https://github.com/tanahiro1610/geniac-handson-practice.git ~/viking-eval
cd ~/viking-eval && git pull -q
```

1. LIBERO のシミュレータのイメージを作る（約1時間。GPU は使わない）

```bash
cd ~/geniac_prize_2026_code
CAPX_IMAGE_DIR=/scratch/$USER/capx-queue/images sbatch -p part-group_1a6e94 singularity/build.sbatch env-libero
```

2. タスクパックとキュー設定を作る（`/scratch` を見るので計算ノードで）

```bash
srun -p part-group_1a6e94 -c 1 --mem=4G -t 00:10:00 bash -c '
J=~/viking-eval/viking_eval_jobs/evalB_cmp; P=~/capx-venv/bin/python
$P $J/make_cmp_pack.py ~/capx-queue/pack-cmp
$P $J/make_cmp_pack.py ~/capx-queue/pack-cmp-smoke --robosuite cube_lifting --libero libero_goal_7 --robosuite-trials 2 --libero-trials 2
$P $J/make_queue_cmp.py ~/capx-queue/pack-cmp ~/capx-queue/queue-cmp.yaml
$P $J/make_queue_cmp.py ~/capx-queue/pack-cmp-smoke ~/capx-queue/queue-cmp-smoke.yaml'
```

`master_seed` が無いと止まります。そのときは `~/capx-queue/queue.yaml` に `master_seed: 20261116` の1行を足してからやり直します。

3. 試し流し（Qwen3.8 だけ、2タスク × 2試行）

```bash
sbatch --export=ALL,WHO=q38,SUB_ID=smoke-1,CONFIG=$HOME/capx-queue/queue-cmp-smoke.yaml ~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
# submit が終わったら worker を1本
cd ~/geniac_prize_2026_code
env -i PATH="$PATH" HOME="$HOME" LANG="$LANG" CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python \
  sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=256G -t 03:00:00 \
    --job-name=evalB-cmp-smoke --export=ALL scripts/evalq/worker.sbatch \
    --config ~/capx-queue/queue-cmp-smoke.yaml --max-jobs 1
```

確かめること：`runs/<run_id>/<subset>/submission-out/logs/vllm.log` でモデルが立ち上がっていること、`results/viking-q38__smoke-1__*.json` で cube_lifting が 2/2 に近いこと。

4. 本番（2つのモデルを同時に）

```bash
sbatch --export=ALL,WHO=q36,SUB_ID=cmp-1 ~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
sbatch --export=ALL,WHO=q38,SUB_ID=cmp-1 ~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
# 両方の submit が終わったら worker を2本（それぞれ GPU 1枚）
cd ~/geniac_prize_2026_code
for i in 1 2; do
env -i PATH="$PATH" HOME="$HOME" LANG="$LANG" CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python \
  sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=256G -t 40:00:00 \
    --job-name=evalB-cmp-worker --export=ALL scripts/evalq/worker.sbatch \
    --config ~/capx-queue/queue-cmp.yaml --max-jobs 1
done
```

5. 結果

```bash
~/capx-venv/bin/python -m capx.cli.main evalq status --config ~/capx-queue/queue-cmp.yaml
```

結果は `<root>/results/agent0-reference__cmp-1__*.json`（Qwen3.6）と `viking-q38__cmp-1__*.json`（Qwen3.8）。
`subsets.robosuite` と `subsets.libero` の `leaderboard.overall_success_rate` を見ます。
