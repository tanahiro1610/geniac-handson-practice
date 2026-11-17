# 評価B：CaP-Agent0 のモデル比較・評価Aとの比較

## 今回（2026-11-17）: 評価Aと同じタスク・seed で、GPU 4枚

評価A（Qwen3.8-27B）と同じタスク・同じ seed で、評価B（CaP-Agent0 の参照実装を評価キューで動かす）を回す。
モデルは Qwen3.8-27B（`WHO=q38`、評価Aと比べる）と Qwen3.6-27B（`WHO=q36`、参照実装そのまま、モデルの差を見る）。

| GPU | 中身 | 試行 | 持ち時間（上限） | 目安 |
| --- | --- | --- | --- | --- |
| 1 | q38・Robosuite 7タスク × seed 401〜450 | 350 | 29.2 時間 | 約14時間 |
| 2 | q36・同上 | 350 | 29.2 時間 | 約14時間 |
| 3 | q38・LIBERO-PRO 30タスク × 評価Aの seed 50個（441〜450、491〜500、541〜550、591〜600、641〜650） | 1500 | 125 時間 | 13〜25時間 |
| 4 | q36・同上 | 1500 | 125 時間 | 13〜25時間 |

- LIBERO-PRO は公開パックの `libero_<goal|object|spatial>_<n>` の env に `suite_name`（`libero_goal_with_mug`・`libero_object_swap`・`libero_spatial_swap`）を渡して作る。タスク名・指示文・seed は評価Aと同じ
- 1試行のステップ上限は評価Bの既定（LIBERO 8000）。評価A（4000）にそろえるなら `--libero-steplimit 4000`
- Robosuite と LIBERO はキュー（root）を分ける。worker は自分のキューの仕事なら何でも取るため

```bash
# 0. 最新にする
cd ~/viking-eval && git pull -q

# 1. LIBERO のシミュレータのイメージを作る（約1時間。GPU なし）
cd ~/geniac_prize_2026_code
CAPX_IMAGE_DIR=/scratch/$USER/capx-queue/images sbatch -p part-group_1a6e94 singularity/build.sbatch env-libero

# 2. パックとキュー設定（/scratch を見るので計算ノードで）
srun -p part-group_1a6e94 -c 1 --mem=4G -t 00:10:00 bash -c '
J=~/viking-eval/viking_eval_jobs/evalB_cmp; P=~/capx-venv/bin/python
$P $J/make_cmp_pack.py ~/capx-queue/pack-rs50 --libero --robosuite-trials 50 --seeds 401-450
$P $J/make_cmp_pack.py ~/capx-queue/pack-lp50 --robosuite --libero-pro --libero-trials 50
$P $J/make_cmp_pack.py ~/capx-queue/pack-rs50-smoke --robosuite cube_lifting --libero --robosuite-trials 4 --seeds 401-404
$P $J/make_cmp_pack.py ~/capx-queue/pack-lp50-smoke --robosuite --libero-pro --libero-trials 1
for k in rs50 lp50 rs50-smoke lp50-smoke; do $P $J/make_queue_cmp.py ~/capx-queue/pack-$k ~/capx-queue/queue-$k.yaml; done'
```

`master_seed が無い` と止まったら、`~/capx-queue/queue.yaml` に `master_seed: 20261116` を足してやり直す。

```bash
# 3. 試し流し（q38 だけ。Robosuite は cube_lifting × 4、LIBERO-PRO は 30タスク × 1）
#    1 のイメージができてから
S=~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
a=$(sbatch --parsable --export=ALL,WHO=q38,SUB_ID=smoke-1,CONFIG=$HOME/capx-queue/queue-rs50-smoke.yaml $S)
b=$(sbatch --parsable --export=ALL,WHO=q38,SUB_ID=smoke-1,CONFIG=$HOME/capx-queue/queue-lp50-smoke.yaml $S)
module load singularitypro/4.1   # worker は env -i で投げるので、ここで PATH に singularity を入れておく
cd ~/geniac_prize_2026_code
W="env -i PATH=$PATH HOME=$HOME LANG=$LANG CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=180G --export=ALL"
$W --dependency=afterok:$a -t 03:00:00 --job-name=evalB-smoke-rs scripts/evalq/worker.sbatch --config ~/capx-queue/queue-rs50-smoke.yaml --max-jobs 1
$W --dependency=afterok:$b -t 04:00:00 --job-name=evalB-smoke-lp scripts/evalq/worker.sbatch --config ~/capx-queue/queue-lp50-smoke.yaml --max-jobs 1
```

試し流しで確かめること:
- `vllm.log` に Qwen3.8-27B が立ち上がった記録がある
- Robosuite: cube_lifting が 4/4 に近い。seed 401 の動画の最初の場面が、評価Aの cube_lifting seed 401 と同じ
- LIBERO-PRO: 30タスクとも env が作れた（`env-libero-*.log` に `KeyError`・`not found`・`bddl` のエラーが無い）。
  goal（with_mug）の動画にマグカップが映り、object・spatial の配置が評価Aの seed 441 と同じ

```bash
# 4. 本番（4本。同じキューへの submit は1本ずつ順に）
S=~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh
r1=$(sbatch --parsable --export=ALL,WHO=q38,SUB_ID=rs50-1,CONFIG=$HOME/capx-queue/queue-rs50.yaml $S)
r2=$(sbatch --parsable --dependency=afterany:$r1 --export=ALL,WHO=q36,SUB_ID=rs50-1,CONFIG=$HOME/capx-queue/queue-rs50.yaml $S)
l1=$(sbatch --parsable --export=ALL,WHO=q38,SUB_ID=lp50-1,CONFIG=$HOME/capx-queue/queue-lp50.yaml $S)
l2=$(sbatch --parsable --dependency=afterany:$l1 --export=ALL,WHO=q36,SUB_ID=lp50-1,CONFIG=$HOME/capx-queue/queue-lp50.yaml $S)
module load singularitypro/4.1   # worker は env -i で投げるので、ここで PATH に singularity を入れておく
cd ~/geniac_prize_2026_code
W="env -i PATH=$PATH HOME=$HOME LANG=$LANG CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=16 --mem=180G --export=ALL"
$W --dependency=afterok:$r1 -t 32:00:00 --job-name=evalB-rs50 scripts/evalq/worker.sbatch --config ~/capx-queue/queue-rs50.yaml --max-jobs 1
$W --dependency=afterok:$r2 -t 32:00:00 --job-name=evalB-rs50 scripts/evalq/worker.sbatch --config ~/capx-queue/queue-rs50.yaml --max-jobs 1
$W --dependency=afterok:$l1 -t 48:00:00 --job-name=evalB-lp50 scripts/evalq/worker.sbatch --config ~/capx-queue/queue-lp50.yaml --max-jobs 1
$W --dependency=afterok:$l2 -t 48:00:00 --job-name=evalB-lp50 scripts/evalq/worker.sbatch --config ~/capx-queue/queue-lp50.yaml --max-jobs 1
```

結果: `<root>/results/viking-q38__<SUB_ID>__*.json`（Qwen3.8）と `agent0-reference__<SUB_ID>__*.json`（Qwen3.6）。
root は `~/capx-queue/queue-<k>.yaml` の `root:`（例 `.../root-pack-rs50`）。

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
