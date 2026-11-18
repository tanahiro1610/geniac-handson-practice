# bv1api：baseline-v1 の評価B を、評価A と同じ API で回す

素の CaP-Agent0（`bv1low` / `bv1lowlc`）は、タスクによって評価A と違う API で動いていた。

| タスク | 評価A | 素の評価B | bv1api |
| --- | --- | --- | --- |
| cube_lifting / stack / restack | `FrankaControlApiReducedSkillLibrary` | 同じ | 同じ |
| nut_assembly | 同上＋取っ手の持ち方のヒント入りプロンプト | 汎用プロンプト | 評価A と同じ |
| spill_wipe | `…SkillLibrarySpillWipe`（スポンジ分 `tcp_offset`）＋拭き方のプロンプト | 汎用（補正なし） | 評価A と同じ |
| two_arm_lift | `…SkillLibraryBimanual`（低レベル） | `FrankaTwoArmLiftApi`（高レベル） | 評価A と同じ |
| two_arm_handover | `…SkillLibraryBimanualHandover`（低レベル） | `FrankaHandoverApi`（高レベル） | 評価A と同じ |
| LIBERO | `FrankaLiberoApiReducedSkillLibrary`＋スキル14個 | `FrankaLiberoApi` | 評価A と同じ |

やり方は運営ベースラインの提出手順（`geniac_prize_2026_baseline/docs/tutorial/10_upload.md`）と同じ。
`capx-submission-bv1.sif` の上に `submission/install.sh` を当てる。

install.sh がすること：
- `skill-library.patch` を当てる
- `trial-state.patch` を当てる（ルールブック §8.4：試行ごとに API の状態を戻す）
- `env_configs/gateway/*.yaml` を評価A の API・プロンプトに置き換える
- `runner.yaml` の `task_map` を足す

私たちは `CAPX_RUNNER_CONFIG` で別の runner を読むので、同じ `task_map` を入れた `runner-baseline-v1-api.yaml` も入れる。

各 YAML の API とプロンプトは評価A の設定（`configs/capx/geniac_prize/`）と一致することを確認済み（2026-11-18、baseline `646c076`）。違うのはゴールの1行だけで、ゲートウェイが渡す指示文に置き換わる。

| ファイル | 中身 |
| --- | --- |
| `runner-baseline-v1-api.yaml` | baseline-v1 の runner に task_map 4件を足したもの |
| `capx-submission-bv1api.def.in` | bv1 のイメージ＋ install.sh。API 名が無ければビルドを止める |
| `prepare_bv1api.sh` | ベースラインを clone し、ビルド材料を `/scratch/$USER/capx-queue/bv1api-build` に置く |
| `build_bv1api.sbatch` | イメージを作り、中の API と task_map を表示する（数分） |
| `submission-bv1api.yaml` | Robosuite 用（`WHO=bv1api`）。bv1lowlc と同じ設定（BF16・32768・文脈 131072・思考 low・アンサンブルあり） |
| `submission-bv1api-libero.yaml` | LIBERO 用（`WHO=bv1apilib`）。上と同じで、アンサンブルなし（評価A の LIBERO と同じ） |

評価A と残る差：
- 時間の決め方：ジョブ全体の予算（試行数×300秒）と、1試行2400秒の違い
- 画像差分を担当するモデル：同じモデルか、別サーバの思考ありモデルか
- Robosuite での Molmo2 の補助

```bash
# 1. 準備（ログインノードでよい）
cd ~/viking-eval && git pull -q
bash ~/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/prepare_bv1api.sh

# 2. イメージ（計算ノードのジョブ、数分）。最後に各タスクの API と task_map が出る
sbatch ~/viking-eval/viking_eval_jobs/evalB_cmp/bv1api/build_bv1api.sbatch

# 3. 試し流し用のパック（spill_wipe と two_arm_lift を 8 試行ずつ＝16試行・16レーン）
srun -p part-group_1a6e94 -c 1 --mem=4G -t 00:10:00 bash -c '
cd ~/geniac_prize_2026_code
J=~/viking-eval/viking_eval_jobs/evalB_cmp; P=~/capx-venv/bin/python
$P $J/make_cmp_pack.py ~/capx-queue/pack-api-smoke --robosuite spill_wipe two_arm_lift --libero --robosuite-trials 8 --seeds 401-408
$P $J/make_queue_cmp.py ~/capx-queue/pack-api-smoke ~/capx-queue/queue-api-smoke.yaml | head -1'

# 4. 試し流し（Robosuite と LIBERO-PRO、GPU 2枚）
S=~/viking-eval/viking_eval_jobs/evalB_cmp/submit.sh; Q=$HOME/capx-queue
a=$(sbatch --parsable --export=ALL,WHO=bv1api,SUB_ID=api-smoke-1,CONFIG=$Q/queue-api-smoke.yaml $S)
b=$(sbatch --parsable --export=ALL,WHO=bv1apilib,SUB_ID=api-smoke-1,CONFIG=$Q/queue-lp50-smoke.yaml $S)
module load singularitypro/4.1
cd ~/geniac_prize_2026_code
W="env -i PATH=$PATH HOME=$HOME LANG=$LANG CAPX_EVALQ_PYTHON=$HOME/capx-venv/bin/python sbatch -p part-group_1a6e94 --gres=gpu:1 --cpus-per-task=8 --mem=160G --export=ALL"
$W --dependency=afterok:$a -t 04:00:00 --job-name=evalB-api-rs scripts/evalq/worker.sbatch --config $Q/queue-api-smoke.yaml --max-jobs 1
$W --dependency=afterok:$b -t 05:00:00 --job-name=evalB-api-lp scripts/evalq/worker.sbatch --config $Q/queue-lp50-smoke.yaml --max-jobs 1
```

試し流しで確かめること：
- ビルドの最後の表示で、各 YAML の `apis:` が上の表の bv1api 列どおり
- 生成コード（`summary.txt` の `Generated program:`）が使っている関数
  - two_arm_lift：`solve_ik_arm0` / `move_to_joints_arm0` を使い、`get_handle0_pos` は使わない（使うと NameError）
  - LIBERO：`open_drawer_by_handle` などの追加スキルを使う
- LIBERO の `vllm.log`：候補9個の呼び出しが無い（アンサンブルなし）
- spill_wipe の成功数（素の評価B では 0/50、評価A では 37/50）

本番は前回と同じパック・キューに、新しい SUB_ID で入れる。結果は `viking-bv1api__…` / `viking-bv1apilib__…` という名前になるので、前回の結果とは混ざらない。
- Robosuite：`queue-rsx` / `queue-rsy` に `WHO=bv1api`
- LIBERO-PRO：`queue-lpa` / `queue-lpb` に `WHO=bv1apilib`
