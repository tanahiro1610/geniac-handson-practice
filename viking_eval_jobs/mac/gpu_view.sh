#!/bin/bash
# For team members: every INTERVAL seconds, fetch the GPU status page that the publisher's Mac pushes to
# the `status` branch of the private share repo, and keep it open in the browser. No cluster access needed.
#   git clone -b status --depth 1 https://github.com/<owner>/viking-gpu-status.git ~/viking-gpu-status
#   bash ~/viking-gpu-status/gpu_view.sh        (stop with Ctrl+C)
# Works on macOS and Linux, and on Windows in Git Bash.
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HOME/viking_gpu_status.html}
INTERVAL=${INTERVAL:-60}
ERR=$(mktemp)
trap 'rm -f "$ERR"; echo; echo stopped; exit 0' INT TERM

git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "$DIR が git のクローンではありません（README の手順で clone してください）"; exit 1; }

open_page() {
  if command -v open >/dev/null 2>&1; then open "$1"
  elif command -v cygpath >/dev/null 2>&1; then cmd.exe //c start "" "$(cygpath -w "$1")"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1
  else echo "ブラウザで $1 を開いてください"; fi
}

first=1
while true; do
  if git -C "$DIR" fetch -q --depth 1 origin status 2>"$ERR" \
     && git -C "$DIR" show FETCH_HEAD:index.html > "$OUT.tmp" 2>>"$ERR"; then
    mv "$OUT.tmp" "$OUT"
    echo "$(date +%H:%M:%S) updated $OUT"
    if [ $first = 1 ]; then open_page "$OUT"; first=0; fi
  else
    rm -f "$OUT.tmp"
    echo "$(date +%H:%M:%S) 取得に失敗しました: $(head -c 200 "$ERR")"
  fi
  sleep "$INTERVAL"
done
