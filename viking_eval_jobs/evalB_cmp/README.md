# 評価B：CaP-Agent0 のモデル比較・評価Aとの比較

## 今回（2026-11-17）: Robosuite 7タスク × 50試行、seed 401〜450（評価Aと同じ）

評価A（Qwen3.8-27B、seed 401〜450）と同じタスク・seed で、評価B（CaP-Agent0 の参照実装を評価キューで動かす）を回す。

| 本 | モデル | 比べる相手 | 分かること |
| --- | --- | --- | --- |
| ① | Qwen3.8-27B（`WHO=q38`） | 評価A（Robosuite 178/350） | 評価の方式の差（思考あり・時間ルールなど） |
| ② | Qwen3.6-27B（`WHO=q36`、参照実装そのまま） | ① | モデルの差 |

1本 350試行。持ち時間は 350 × 300秒 = 29.2時間（上限）、参照実装の実績から実際は約14時間。GPU は1本に1枚。

```bash
# 1. パックとキュー設定を作る（/scratch を見るので計算ノードで）
srun -p part-group_1a6e94 -c 1 --mem=4G -t 00:10:00 bash -c '
J=~/viking-eval/viking_eval_jobs/evalB_cmp; P=~/capx-venv/bin/python
$P $J/make_cmp_pack.py ~/capx-queue/pack-rs50 --libero --robosuite-trials 50 --seeds 401-450
$P $J/make_cmp_pack.py ~/capx-queue/pack-rs50-smoke --robosuite cube_lifting --libero --robosuite-trials 4 --seeds 401-404
$P $J/make_queue_cmp.py ~/capx-queue/pack-rs50 ~/capx-queue/queue-rs50.yaml
$P $J/make_queue_cmp.py ~/capx-queue/pack-rs50-smoke ~/capx-queue/queue-rs50-smoke.yaml'

# 2. 試し流し（Qwen3.8、cube_lifting × 4試行）
sbatch --export=ALL,WHO=q38,SUB_ID=rs50-smoke-1,CONFIG=$HOME/capx-queue/queue-rs50-smoke.yaml ~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
#    submit のジョブが終わったら worker
cd ~/geniac_prize_2026_code
env -i PATH="$PATH" HOME="$HOME" LANG="$LANG" CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python \
  sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=256G -t 03:00:00 \
    --job-name=evalB-rs50-smoke --export=ALL scripts/evalq/worker.sbatch \
    --config ~/capx-queue/queue-rs50-smoke.yaml --max-jobs 1

# 3. 本番（① から。② は ① が終わってから、または班に断ってから同時に）
sbatch --export=ALL,WHO=q38,SUB_ID=rs50-1,CONFIG=$HOME/capx-queue/queue-rs50.yaml ~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
cd ~/geniac_prize_2026_code
env -i PATH="$PATH" HOME="$HOME" LANG="$LANG" CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python \
  sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=256G -t 32:00:00 \
    --job-name=evalB-rs50 --export=ALL scripts/evalq/worker.sbatch \
    --config ~/capx-queue/queue-rs50.yaml --max-jobs 1
```

試し流しで確かめること:
- `runs/<run_id>/robosuite/submission-out/logs/vllm.log` に Qwen3.8-27B が立ち上がった記録がある
- `results/viking-q38__rs50-smoke-1__*.json` の cube_lifting が 4/4 に近い
- `submission-out/cube_lifting/` の seed 401 の動画の最初の場面が、評価Aの cube_lifting seed 401 の動画と同じ（同じ seed で同じ場面になるかの確認）

---

## 以前の案（モデル比較、ランダム seed・元の LIBERO）

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
