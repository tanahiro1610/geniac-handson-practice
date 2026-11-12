"""使い方: <ベースラインの .venv/bin/python> make_chat_template.py <モデルのフォルダ> <出力する .jinja>"""
import sys
from pathlib import Path
from geniac_baseline.collect.template import TemplateError, _SYSTEM_CHECKS, derive, read_model_template

model_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
text = read_model_template(model_dir)
try:
    text = derive(text)  # Qwen3.8 系: 推論の深さの既定を low にし、画像チェックを外す（ベースラインと同じ）
    how = "Qwen3.8 方式（推論の深さ low ＋ 画像チェックを外した）"
except TemplateError:
    removed = 0
    for block in _SYSTEM_CHECKS:  # それ以外: system メッセージの画像・動画チェックがあれば外す
        if text.count(block) == 1:
            text = text.replace(block, "")
            removed += 1
    how = f"画像・動画チェックを {removed} か所外した（0 ならモデルの template そのまま）"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(text)
print(f"{how} -> {out}")
