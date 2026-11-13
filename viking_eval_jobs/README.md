# VIKING 評価班 ジョブスクリプト（GENIAC-PRIZE 2026 テーマ2）

チーム VIKING（team05）評価班が使っている Slurm ジョブスクリプト一式です。
チームの Git ができるまでの仮置き場です。

## 使い方（クラスタのログインノードで）

```bash
git clone -b eval-jobs --depth 1 https://github.com/tanahiro1610/geniac-handson-practice.git ~/viking-eval
mkdir -p ~/jobs ~/logs
cp ~/viking-eval/viking_eval_jobs/*.sh ~/viking-eval/viking_eval_jobs/*.py ~/jobs/
```

更新を取り込むとき：

```bash
cd ~/viking-eval && git pull && cp viking_eval_jobs/*.sh viking_eval_jobs/*.py ~/jobs/
```

## ファイル

| ファイル | 用途 | 例 |
|---|---|---|
| `evalA.sh` | 評価A（ベースライン repo）。1タスク×seed 401-450 | `sbatch --export=ALL,TASK=cube_lifting,OFF=1700 ~/jobs/evalA.sh` |
| 〃（配列） | 7タスクを同時2本まで | `sbatch --array=0-6%2 ~/jobs/evalA.sh` |
| `evalA_libero.sh` | 評価A の LIBERO-PRO（30タスク、運営の eval_base_libero.yaml と同じ条件）。OFF は自動で選ぶ | `sbatch --array=0-29%3 ~/jobs/evalA_libero.sh` |
| `eval_sft.sh` | SFT 済みモデルの学習前/学習後比較 | 手順書「SFT済みモデルの評価手順書」参照 |
| `make_chat_template.py` | Qwen 系チャットテンプレートの自動生成（eval_sft.sh が呼ぶ） | — |
| `copy_to_shared.sh` | モデル・アダプタを共有領域へコピー（権限付与つき） | `bash ~/jobs/copy_to_shared.sh <元> <先>` |
| `evalB_submit.sh` | 評価B（運営の evalq）へ CaP-Agent0 を投入 | `sbatch --export=ALL,SUB_ID=robosuite-1 ~/jobs/evalB_submit.sh` |
| `queue.yaml.example` | 評価B のキュー設定ひな形（`<user>` を置換して `~/capx-queue/queue.yaml` へ） | — |
| `download_models.sh` | 評価A用モデル（Qwen3.8-27B / Molmo2-8B）のダウンロード | `sbatch ~/jobs/download_models.sh` |
| `pick_videos.sh` | 評価Aの動画を各タスク成功・失敗 N 本ずつ選んで `~/videos_pick.tgz` に | `sbatch ~/jobs/pick_videos.sh` |
| `pack_outputs.sh` | 出力一式を tgz にまとめる（mp4 除く） | `bash ~/jobs/pack_outputs.sh` |

## Mac で GPU の使用状況を見る

`mac/gpu_watch.sh` は **Mac で動かす**スクリプトです。30 秒ごとに `ssh gmo` で squeue を取り、`~/gpu_status.html` を書き直します（ブラウザで開いておけば自動で更新）。

```bash
bash viking_eval_jobs/mac/gpu_watch.sh     # Ctrl+C で止める
```

## 必ず守ること

- **`--mem` を必ず付ける**（付けないとノードの全メモリを要求し、チーム全体が止まる）。
- **ポートの OFF（オフセット）を他ジョブと重ねない**。学習班 0〜900、評価班 1000〜1900（A配列 1000〜1600、単発 1700、SFT 1800）。
  スクリプトは起動時に使用ポートを確認し、重なっていたら `FATAL: port conflict` で止まります。
- チームの GPU は 4 枚。評価で同時に使うのは原則 2〜3 本まで（班長と調整）。
- 長いスクリプトをターミナルに貼り付けない（壊れます）。このリポジトリから取ってください。

## 詳しい手順書

- 評価ベースライン実行手順書（評価A・評価B）
- SFT済みモデルの評価手順書
- 出力ファイルの解説
- SAM3 `Inference failed` の対応

（リンクはチームの共有先を参照）
