# 評価A・評価B を「タスクごとに良い方の API」でやり直す（2026-11-18）

## どちらの API を使うか

| タスク | 評価A の API の結果 | 素の評価B の API の結果 | 使う API | 根拠 |
| --- | --- | --- | --- | --- |
| cube_lifting / stack / restack | — | — | （A と B で同じ API） | — |
| spill_wipe | 37/50 | 0/50 | **評価A**（`…SkillLibrarySpillWipe`＋拭き方のプロンプト） | スポンジの `tcp_offset` が無いと拭けない |
| nut_assembly | 0/50 | 0/50 | **評価A**（取っ手の持ち方のヒント入りプロンプト） | API は同じで、プロンプトのヒントだけ違う |
| two_arm_lift | 15/50 | 28/50 | **評価B**（`FrankaTwoArmLiftApi`） | 取っ手の位置を返す関数があり、位置指定で動かせる |
| two_arm_handover | 0/50 | 0/50 | 評価A のまま（保留） | 差の材料が無い |
| LIBERO-PRO | 511/1500 | 結果待ち（lpa/lpb、seed 441-450） | 評価A のまま（保留） | lpa/lpb を評価A の同じ seed と比べてから決める |

注意：
- 素の評価B の数字は、文脈長の超過があったとき（文脈 65536）のもの。文脈を広げたやり直し（43111/43112）で数字が変わったら見直す。
- two_arm_handover を評価A で高レベル API（`FrankaHandoverApi`）にするときは注意がいる。評価A のシミュレータは観測に正解のセグメンテーションを入れていて、この API はそれがあると使う（本番・評価B は RGB と深度だけ）。そのままだと評価A だけ「正解を見た」点になる。two_arm_lift のシミュレータは入れていないので、問題ない。
- ルールブック §8.3 では、タスク専用の高レベル API を作ることは認められている。ただし本番のタスクは非公開で、「そうした手法で簡単に解けるようには作っていない」とある。two_arm_lift の高レベル API が本番で効くとは限らない。

## やり直す範囲

- **評価A：two_arm_lift だけ**（`two_arm_lift_hl.yaml`）。評価A は1試行ずつ時間（2400秒）が決まっていて、ほかのタスクの影響を受けない。そのため、API を変えないタスクは前の結果をそのまま使える。
- **評価B：Robosuite 7タスク全部**（`WHO=bv1best`）。評価B はジョブ全体の時間予算（試行数×300秒）を同じジョブのタスクで分け合う。1タスクでも API が変わると、ほかのタスクの使える時間も変わるので、全部回す。

## 評価A：two_arm_lift を高レベル API で（50試行）

いちばん簡単なのは `evalA_hl.sh`（`~/jobs/evalA.sh` と同じ中身で、タスクの設定ファイルを替えられる版）：
`sbatch ~/viking-eval/viking_eval_jobs/evalA_best/evalA_hl.sh` → `runs/evalA_hl_two_arm_lift_401-450`。
以下は spec を手で作るやり方。

`two_arm_lift_hl.yaml` は、評価A の two_arm_lift の設定の3か所だけを変えたもの：
- API
- プロンプト（評価B のもの。ゴールの文は評価A の文）
- 知覚サーバ（OWLv2・SAM2・GraspNet・pyroki）

multi-turn、アンサンブル、画像差分、モデル、時間はそのまま。OWLv2 と SAM2.1 の重みは、初回に HF から取得する。

`make_spec.py` は、前の評価A の run の `plan.json`（実際に回した設定そのもの）から、タスクと出力先だけを替えた spec を作る。

```bash
# ベースラインの置き場所で（前の評価A と同じ環境）。OFF=1900 は評価班の空き番号の例。使う前に空きを確認する
cd <geniac_prize_2026_baseline の場所>
python ~/viking-eval/viking_eval_jobs/evalA_best/make_spec.py \
  runs/evalA_base_two_arm_lift_401-450/plan.json \
  runs/specs/evalA_hl_two_arm_lift.yaml \
  --output-dir runs/evalA_hl_two_arm_lift_401-450 --port-offset 1900 \
  --task two_arm_lift=$HOME/viking-eval/viking_eval_jobs/evalA_best/two_arm_lift_hl.yaml
geniac-baseline eval plan --spec runs/specs/evalA_hl_two_arm_lift.yaml   # 出力先があると止まる
# GPU のジョブで: bash runs/evalA_hl_two_arm_lift_401-450/run.sh （~/jobs/evalA.sh と同じやり方で）
geniac-baseline eval score runs/evalA_hl_two_arm_lift_401-450 --json score.json
```

## 評価B：bv1best（Robosuite 7×50）

イメージは `capx-submission-bv1api.sif`（`../evalB_cmp/bv1api/`）。

イメージを作るときに、CaP-Agent0 の元の設定を `*_hl.yaml` として残している（two_arm_lift・two_arm_handover・LIBERO）。そのため、どちらの API にするかは runner の `task_map` で選べる。

`runner-bv1-best.yaml` は、two_arm_lift だけを `franka_two_arm_lift_hl.yaml` にしたもの。

```bash
S=~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh; Q=$HOME/capx-queue
x=$(sbatch --parsable --export=ALL,WHO=bv1best,SUB_ID=best-1,CONFIG=$Q/queue-rsx.yaml $S)
y=$(sbatch --parsable --export=ALL,WHO=bv1best,SUB_ID=best-1,CONFIG=$Q/queue-rsy.yaml $S)
module load singularitypro/4.1
cd ~/geniac_prize_2026_code
W="env -i PATH=$PATH HOME=$HOME LANG=$LANG CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=8 --mem=160G --export=ALL"
$W --dependency=afterok:$x -t 20:00:00 --job-name=evalB-best-rsx scripts/evalq/worker.sbatch --config $Q/queue-rsx.yaml --max-jobs 1
$W --dependency=afterok:$y -t 20:00:00 --job-name=evalB-best-rsy scripts/evalq/worker.sbatch --config $Q/queue-rsy.yaml --max-jobs 1
```
