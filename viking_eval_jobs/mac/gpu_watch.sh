#!/bin/bash
# Run on your Mac (not on the cluster). Every INTERVAL seconds it asks the cluster for the
# team's jobs over ssh and rewrites ~/gpu_status.html, a dashboard that reloads itself.
#   bash gpu_watch.sh            (stop with Ctrl+C)
#   INTERVAL=60 bash gpu_watch.sh
# Optional ~/.gpu_watch_names: one "user_000xx_1a6e94 表示名" per line, to show names instead of IDs.
# Needs `ssh gmo` to work. One ssh connection is kept open, so the passphrase is asked once.
INTERVAL=${INTERVAL:-30}
HOST=${HOST:-gmo}
PART=${PART:-part-group_1a6e94}
TEAM_GPUS=${TEAM_GPUS:-4}
OUT=${OUT:-$HOME/gpu_status.html}
HIST=${HIST:-$HOME/.gpu_watch_history}
NAMES=${NAMES:-$HOME/.gpu_watch_names}
CP="$HOME/.ssh/cm-gpuwatch-%r@%h:%p"
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CP" -o ControlPersist=10m -o ConnectTimeout=15 "$HOST")

"${SSH[@]}" true || { echo "ssh $HOST failed"; exit 1; }
ME=$("${SSH[@]}" 'echo $USER')
trap '"${SSH[@]}" -O exit >/dev/null 2>&1; echo; echo stopped; exit 0' INT TERM
touch "$HIST" "$NAMES"

render() {
  local data="$1" now="$2" err="$3" epoch
  epoch=$(date +%s)
  echo "$data" | awk -F'|' -v me="$ME" -v total="$TEAM_GPUS" -v now="$now" -v epoch="$epoch" \
      -v interval="$INTERVAL" -v part="$PART" -v err="$err" -v hist="$HIST" -v names="$NAMES" '
    function e(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
    function gpus(s,  n){ if (s !~ /gpu/) return 0; n=s; sub(/.*gpu[^0-9]*/,"",n); n+=0; return (n>0?n:1) }
    function secs(t,  d,p,a,n){ if (t !~ /^[0-9]/) return 0; d=0
      if (index(t,"-")) { split(t,p,"-"); d=p[1]+0; t=p[2] }
      n=split(t,a,":"); if (n==3) return d*86400+a[1]*3600+a[2]*60+a[3]
      if (n==2) return d*86400+a[1]*60+a[2]; return d*86400+a[1] }
    function hm(s,  h,m){ h=int(s/3600); m=int((s%3600)/60); return (h>0? h "h " m "m" : m "m") }
    function hue(s,  i,h,c){ h=7; for (i=1;i<=length(s);i++){ c=index("0123456789abcdefghijklmnopqrstuvwxyz_-",substr(s,i,1)); h=(h*31+c)%360 } return h }
    function who(u){ return (u in alias ? alias[u] : (u ~ /^user_[0-9]+/ ? substr(u,6,5) : u)) }
    function chip(r,  c){ c="#64748b"
      if (r ~ /GRES/) c="#f59e0b"; else if (r ~ /Cpu/) c="#f97316"; else if (r ~ /Mem/) c="#ef4444"
      else if (r ~ /Dependency/) c="#8b5cf6"; else if (r ~ /ArrayTaskLimit/) c="#06b6d4"; else if (r ~ /Priority|Resources/) c="#3b82f6"
      return "<span class=\"chip\" style=\"--c:" c "\">" e(r) "</span>" }
    BEGIN { while ((getline line < names) > 0) { split(line,a," "); if (a[1]!="") { sub(/^[^ ]+ +/,"",line); alias[a[1]]=line } } }
    NF>=9 {
      for (k=1;k<=NF;k++) gsub(/^ +| +$/,"",$k)
      g=gpus($6)
      if ($4=="RUNNING") {
        nr++; R_id[nr]=$1; R_u[nr]=$2; R_n[nr]=$3; R_g[nr]=g; R_t[nr]=secs($5); R_l[nr]=secs($10); R_c[nr]=$7; R_m[nr]=$8
        used+=g; if ($2==me) mine+=g
      } else { np++; P_id[np]=$1; P_u[np]=$2; P_n[np]=$3; P_g[np]=g; P_r[np]=$9 }
    }
    END {
      if (err=="") { print epoch, used+0 >> hist; close(hist) }
      nh=0; while ((getline line < hist) > 0) { split(line,a," "); nh++; HT[nh]=a[1]; HU[nh]=a[2] }
      free=total-used; if (free<0) free=0
      print "<!DOCTYPE html><html lang=\"ja\"><head><meta charset=\"utf-8\">"
      print "<meta http-equiv=\"refresh\" content=\"" interval+15 "\"><title>GPU " used+0 "/" total " · VIKING</title><style>"
      print ":root{--bg:#0b1020;--card:#121a2f;--line:#1f2a44;--txt:#e6ebf5;--sub:#8b97b3;--free:#1b2540}"
      print "*{box-sizing:border-box}body{margin:0;padding:28px;background:radial-gradient(1200px 600px at 10% -10%,#1b2a55 0,transparent 60%),var(--bg);color:var(--txt);font-family:-apple-system,\"Hiragino Sans\",\"Segoe UI\",sans-serif}"
      print "header{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:22px}h1{margin:0;font-size:22px;letter-spacing:.02em}.sub{color:var(--sub);font-size:13px}"
      print ".live{display:inline-flex;align-items:center;gap:8px;font-size:13px;color:var(--sub)}.dot{width:9px;height:9px;border-radius:50%;background:#22c55e;box-shadow:0 0 0 0 #22c55e88;animation:p 2s infinite}@keyframes p{70%{box-shadow:0 0 0 10px #22c55e00}100%{box-shadow:0 0 0 0 #22c55e00}}"
      print ".grid{display:grid;grid-template-columns:260px 1fr;gap:18px;margin-bottom:18px}.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px}"
      print ".gauge{display:flex;flex-direction:column;align-items:center;justify-content:center}.gauge svg{width:180px;height:180px}.gauge .lab{fill:var(--sub);font-size:13px}"
      print ".stats{display:flex;gap:10px;margin-top:10px;width:100%}.stat{flex:1;text-align:center;background:#0e1528;border-radius:10px;padding:8px}.stat b{display:block;font-size:20px}.stat span{font-size:11px;color:var(--sub)}"
      print ".slots{display:grid;grid-template-columns:repeat(" total ",1fr);gap:12px}.slot{border-radius:14px;padding:14px;min-height:150px;background:var(--free);border:1px dashed #2a3658;display:flex;flex-direction:column;justify-content:space-between}"
      print ".slot.busy{border:1px solid hsl(var(--h) 70% 55% / .6);background:linear-gradient(160deg,hsl(var(--h) 70% 45% / .28),var(--card) 70%)}.slot.me{box-shadow:0 0 0 2px #22c55e inset}"
      print ".slot .gpu{font-size:11px;color:var(--sub);letter-spacing:.1em}.slot .name{font-size:16px;font-weight:700;margin:6px 0 2px;word-break:break-all}.slot .user{font-size:13px;color:hsl(var(--h) 80% 75%)}.slot.free .name{color:#56628a;font-weight:600}"
      print ".bar{height:6px;border-radius:3px;background:#0b1224;overflow:hidden;margin-top:10px}.bar i{display:block;height:100%;background:hsl(var(--h) 75% 55%)}.bar i.warn{background:#ef4444}.meta{display:flex;justify-content:space-between;font-size:12px;color:var(--sub);margin-top:6px}"
      print "h2{font-size:14px;color:var(--sub);font-weight:600;margin:0 0 10px;letter-spacing:.05em}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left}th{color:var(--sub);font-weight:500}tr.me td:first-child{box-shadow:inset 3px 0 #22c55e}"
      print ".chip{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;background:color-mix(in srgb,var(--c) 22%,transparent);color:var(--c);border:1px solid color-mix(in srgb,var(--c) 50%,transparent)}"
      print ".u{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:hsl(var(--h) 75% 60%)}.err{background:#3b1220;border:1px solid #7f1d1d;color:#fecaca;padding:10px 14px;border-radius:10px;margin-bottom:16px}"
      print ".two{display:grid;grid-template-columns:1fr 1fr;gap:18px}.spark{width:100%;height:90px}.empty{color:#56628a;font-size:13px}@media(max-width:900px){.grid,.two{grid-template-columns:1fr}.slots{grid-template-columns:repeat(2,1fr)}}</style></head><body>"
      print "<header><div><h1>VIKING · GPU Dashboard</h1><div class=\"sub\">" e(part) " ・ 自分 = " e(who(me)) "</div></div>"
      print "<div class=\"live\"><span class=\"dot\"></span><span>更新 " now " ・ 次の更新まで <b id=\"cd\">" interval "</b> 秒</span></div></header>"
      if (err!="") print "<div class=\"err\">取得に失敗しました（ネットワークか ssh）： " e(err) "</div>"
      pct=(total>0? used/total : 0); if (pct>1) pct=1; C=2*3.14159*70
      col=(pct>=1?"#ef4444":(pct>=.75?"#f59e0b":"#22c55e"))
      print "<div class=\"grid\"><div class=\"card gauge\"><svg viewBox=\"0 0 180 180\"><circle cx=\"90\" cy=\"90\" r=\"70\" fill=\"none\" stroke=\"#1b2540\" stroke-width=\"14\"/>"
      printf "<circle cx=\"90\" cy=\"90\" r=\"70\" fill=\"none\" stroke=\"%s\" stroke-width=\"14\" stroke-linecap=\"round\" stroke-dasharray=\"%.1f %.1f\" transform=\"rotate(-90 90 90)\"/>", col, C*pct, C
      printf "<text x=\"90\" y=\"98\" text-anchor=\"middle\" fill=\"#e6ebf5\" font-size=\"44\" font-weight=\"800\">%d/%d</text><text x=\"90\" y=\"122\" text-anchor=\"middle\" class=\"lab\">GPU 使用中</text></svg>\n", used, total
      printf "<div class=\"stats\"><div class=\"stat\"><b>%d</b><span>空き GPU</span></div><div class=\"stat\"><b>%d</b><span>走っている</span></div><div class=\"stat\"><b>%d</b><span>待っている</span></div></div></div>\n", free, nr, np
      print "<div class=\"card\"><h2>GPU スロット</h2><div class=\"slots\">"
      s=0
      for (i=1;i<=nr;i++) for (j=1;j<=R_g[i] && s<total;j++) { s++
        h=hue(R_u[i]); lim=R_l[i]; frac=(lim>0? R_t[i]/lim : 0); if (frac>1) frac=1
        printf "<div class=\"slot busy%s\" style=\"--h:%d\"><div><div class=\"gpu\">GPU %d</div><div class=\"name\">%s</div><div class=\"user\">%s</div></div>", (R_u[i]==me?" me":""), h, s, e(R_n[i]), e(who(R_u[i]))
        printf "<div><div class=\"bar\"><i class=\"%s\" style=\"width:%d%%\"></i></div><div class=\"meta\"><span>%s 経過</span><span>%s</span></div></div></div>\n", (frac>.85?"warn":""), frac*100, hm(R_t[i]), (lim>0? "上限 " hm(lim) : "#" e(R_id[i]))
      }
      while (s<total) { s++; printf "<div class=\"slot free\"><div><div class=\"gpu\">GPU %d</div><div class=\"name\">空き</div></div><div class=\"meta\"><span>いつでも使えます</span></div></div>\n", s }
      print "</div></div></div>"
      print "<div class=\"two\"><div class=\"card\"><h2>使用中の GPU（直近）</h2>"
      n0=(nh>240? nh-239 : 1); cnt=nh-n0+1
      if (cnt>=2) {
        W=600; H=90; pts=""; area="0," H " "
        for (i=n0;i<=nh;i++) { x=(i-n0)*W/(cnt-1); y=H-4-(HU[i]/total)*(H-8); pts=pts sprintf("%.1f,%.1f ",x,y); area=area sprintf("%.1f,%.1f ",x,y) }
        area=area W "," H
        printf "<svg class=\"spark\" viewBox=\"0 0 %d %d\" preserveAspectRatio=\"none\"><defs><linearGradient id=\"g\" x1=\"0\" x2=\"0\" y1=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#3b82f6\" stop-opacity=\".45\"/><stop offset=\"1\" stop-color=\"#3b82f6\" stop-opacity=\"0\"/></linearGradient></defs>", W, H
        for (k=1;k<total;k++) printf "<line x1=\"0\" x2=\"%d\" y1=\"%.1f\" y2=\"%.1f\" stroke=\"#1f2a44\" stroke-dasharray=\"3 4\"/>", W, H-4-(k/total)*(H-8), H-4-(k/total)*(H-8)
        printf "<polygon points=\"%s\" fill=\"url(#g)\"/><polyline points=\"%s\" fill=\"none\" stroke=\"#60a5fa\" stroke-width=\"2\"/></svg>", area, pts
        mins=int((HT[nh]-HT[n0])/60); printf "<div class=\"meta\"><span>%d 分前</span><span>今</span></div>", mins
      } else print "<div class=\"empty\">記録をためています（2 回目の更新から表示）</div>"
      print "</div><div class=\"card\"><h2>待っているジョブ</h2>"
      if (np) { print "<table><tr><th>ジョブ</th><th>ユーザー</th><th>名前</th><th>理由</th></tr>"
        for (i=1;i<=np;i++) printf "<tr%s><td>%s</td><td><span class=\"u\" style=\"--h:%d\"></span>%s</td><td>%s</td><td>%s</td></tr>\n", (P_u[i]==me?" class=\"me\"":""), e(P_id[i]), hue(P_u[i]), e(who(P_u[i])), e(P_n[i]), chip(P_r[i])
        print "</table>" } else print "<div class=\"empty\">なし</div>"
      print "</div></div>"
      k=0; for (i=1;i<=nr;i++) if (R_g[i]==0) k++
      if (k) { print "<div class=\"card\" style=\"margin-top:18px\"><h2>GPU を使っていない実行中ジョブ</h2><table><tr><th>ジョブ</th><th>ユーザー</th><th>名前</th><th>CPU</th><th>メモリ</th><th>経過</th></tr>"
        for (i=1;i<=nr;i++) if (R_g[i]==0) printf "<tr><td>%s</td><td><span class=\"u\" style=\"--h:%d\"></span>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", e(R_id[i]), hue(R_u[i]), e(who(R_u[i])), e(R_n[i]), R_c[i], R_m[i], hm(R_t[i])
        print "</table></div>" }
      print "<p class=\"sub\" style=\"margin-top:18px\">理由の色：<span class=\"chip\" style=\"--c:#f59e0b\">GPU 上限</span> <span class=\"chip\" style=\"--c:#f97316\">CPU 上限</span> <span class=\"chip\" style=\"--c:#ef4444\">メモリ上限</span> <span class=\"chip\" style=\"--c:#8b5cf6\">前のジョブ待ち</span> <span class=\"chip\" style=\"--c:#06b6d4\">配列の同時実行数</span> ・ バーは経過時間 / 上限時間（85% を超えると赤）</p>"
      print "<script>let s=" interval ";const c=document.getElementById(\"cd\");setInterval(()=>{s--;if(s<=0){location.reload()}else{c.textContent=s}},1000)</script></body></html>"
    }' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  tail -n 2000 "$HIST" > "$HIST.tmp" 2>/dev/null && mv "$HIST.tmp" "$HIST"
}

first=1
while true; do
  now=$(date "+%H:%M:%S")
  # tres-alloc shows the GPUs a running job really holds (gres/gpu=1), however it asked for them;
  # older Slurm without -O suffixes falls back to %b (the --gres request).
  q1="squeue -p $PART -h -r -O 'JobArrayID:24|,UserName:24|,Name:30|,State:12|,TimeUsed:14|,tres-alloc:100|,NumCPUs:8|,MinMemory:10|,ReasonList:60|,TimeLimit:14|'"
  q2="squeue -p $PART -h -r -o '%i|%u|%j|%T|%M|%b|%C|%m|%R|%l'"
  err=""
  if data=$("${SSH[@]}" "$q1" 2>/dev/null) && echo "$data" | grep -q '|'; then :
  elif ! data=$("${SSH[@]}" "$q2" 2>&1); then err="$data"; data=""; fi
  render "$data" "$now" "$err"
  if [ $first = 1 ]; then open "$OUT" 2>/dev/null || echo "open $OUT in your browser"; first=0; fi
  echo "$now updated $OUT"
  sleep "$INTERVAL"
done
