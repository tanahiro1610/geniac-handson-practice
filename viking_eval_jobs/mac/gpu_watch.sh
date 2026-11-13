#!/bin/bash
# Run on your Mac (not on the cluster). Every INTERVAL seconds it asks the cluster for the
# team's jobs over ssh and rewrites ~/gpu_status.html, which reloads itself in the browser.
#   bash gpu_watch.sh            (stop with Ctrl+C)
#   INTERVAL=60 bash gpu_watch.sh
# Needs `ssh gmo` to work. One ssh connection is kept open, so the passphrase is asked once.
INTERVAL=${INTERVAL:-30}
HOST=${HOST:-gmo}
PART=${PART:-part-group_1a6e94}
TEAM_GPUS=${TEAM_GPUS:-4}
OUT=${OUT:-$HOME/gpu_status.html}
CP="$HOME/.ssh/cm-gpuwatch-%r@%h:%p"
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CP" -o ControlPersist=10m -o ConnectTimeout=15 "$HOST")

"${SSH[@]}" true || { echo "ssh $HOST failed"; exit 1; }
ME=$("${SSH[@]}" 'echo $USER')
trap '"${SSH[@]}" -O exit >/dev/null 2>&1; echo; echo stopped; exit 0' INT TERM

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

render() {
  local data="$1" now="$2" err="$3"
  {
    cat <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="$INTERVAL"><title>GPU 使用状況</title>
<style>
body{font-family:-apple-system,"Hiragino Sans",sans-serif;margin:24px;color:#222;background:#fafafa}
h1{font-size:20px;margin:0 0 4px}.sub{color:#666;font-size:13px;margin-bottom:16px}
.big{font-size:40px;font-weight:700}.bar{display:flex;gap:6px;margin:8px 0 20px}
.slot{width:56px;height:28px;border-radius:6px;background:#e5e5e5}.slot.on{background:#3b82f6}.slot.me{background:#16a34a}
table{border-collapse:collapse;width:100%;background:#fff;margin-bottom:20px;font-size:14px}
th,td{border-bottom:1px solid #eee;padding:6px 10px;text-align:left}th{background:#f3f3f3;font-weight:600}
tr.me td{background:#ecfdf3}.err{color:#b91c1c;font-weight:600}
</style></head><body>
<h1>VIKING GPU 使用状況（$PART）</h1>
<div class="sub">更新 $now ・ ${INTERVAL} 秒ごとに自動更新 ・ 緑 = 自分（$ME）のジョブ</div>
HTML
    if [ -n "$err" ]; then echo "<p class=\"err\">取得に失敗しました：$(echo "$err" | esc)（前回の表示ではありません）</p>"; fi
    echo "$data" | awk -F'|' -v me="$ME" -v total="$TEAM_GPUS" '
      function gpus(s,  n){ if (s !~ /gpu/) return 0; n=s; sub(/.*gpu[^0-9]*/,"",n); n+=0; return (n>0?n:1) }
      function e(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
      NF>=9 {
        for (k=1;k<=NF;k++) { gsub(/^ +| +$/,"",$k) }
        g=gpus($6)
        if ($4=="RUNNING") { used+=g; if ($2==me) mine+=g
          run[++nr]=sprintf("<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>", ($2==me?" class=\"me\"":""), e($1), e($2), e($3), g, $7, $8, e($5))
        } else {
          pend[++np]=sprintf("<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td>%s</td></tr>", ($2==me?" class=\"me\"":""), e($1), e($2), e($3), g, e($9))
        }
      }
      END {
        printf "<div class=\"big\">GPU %d / %d 使用中</div><div class=\"bar\">", used, total
        for (i=1;i<=total;i++) printf "<div class=\"slot%s\"></div>", (i<=mine?" me":(i<=used?" on":""))
        print "</div>"
        print "<h2>走っているジョブ</h2><table><tr><th>ジョブ</th><th>ユーザー</th><th>名前</th><th>GPU</th><th>CPU</th><th>メモリ</th><th>経過</th></tr>"
        for (i=1;i<=nr;i++) print run[i]; if (!nr) print "<tr><td colspan=7>なし</td></tr>"
        print "</table><h2>待っているジョブ</h2><table><tr><th>ジョブ</th><th>ユーザー</th><th>名前</th><th>GPU</th><th>待っている理由</th></tr>"
        for (i=1;i<=np;i++) print pend[i]; if (!np) print "<tr><td colspan=5>なし</td></tr>"
        print "</table>"
      }'
    cat <<'HTML'
<div class="sub">待っている理由：QOSGrpGRES = チームの GPU が埋まっている ／ QOSGrpCpuLimit = CPU ／ QOSGrpMemLimit = メモリ ／ Dependency = 前のジョブ待ち ／ JobArrayTaskLimit = 配列の同時実行数</div>
</body></html>
HTML
  } > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
}

first=1
while true; do
  now=$(date "+%Y-%m-%d %H:%M:%S")
  # tres-alloc shows the GPUs a running job really holds (gres/gpu=1), however it asked for them;
  # older Slurm without -O suffixes falls back to %b (the --gres request).
  q1="squeue -p $PART -h -r -O 'JobArrayID:24|,UserName:24|,Name:30|,State:12|,TimeUsed:14|,tres-alloc:100|,NumCPUs:8|,MinMemory:10|,ReasonList:60|'"
  q2="squeue -p $PART -h -r -o '%i|%u|%j|%T|%M|%b|%C|%m|%R'"
  if data=$("${SSH[@]}" "$q1" 2>/dev/null) && echo "$data" | grep -q '|'; then :
  else data=$("${SSH[@]}" "$q2" 2>&1); fi
  if [ $? -eq 0 ]; then
    render "$data" "$now" ""
  else
    render "" "$now" "$data"
  fi
  if [ $first = 1 ]; then open "$OUT" 2>/dev/null || echo "open $OUT in your browser"; first=0; fi
  echo "$now updated $OUT"
  sleep "$INTERVAL"
done
