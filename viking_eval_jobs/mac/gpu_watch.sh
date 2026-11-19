#!/bin/bash
# Run on your Mac (not on the cluster). Every INTERVAL seconds it asks the cluster for the
# team's jobs over ssh and rewrites ~/gpu_status.html, a dashboard that reloads itself.
#   bash gpu_watch.sh            (stop with Ctrl+C)
#   INTERVAL=60 bash gpu_watch.sh
#   THEME=plain bash gpu_watch.sh   (前の見た目に戻す)
# Optional ~/.gpu_watch_names: one "user_000xx_1a6e94 表示名" per line, to show names instead of IDs.
# RTX PRO 6000 (team VM, no Slurm) is read with nvidia-smi over `ssh rtx`; RTX_HOST= (empty) turns it off.
#   Add its login name to ~/.gpu_watch_names too, e.g. "h_tanaka たな".
# Needs `ssh gmo` to work. One ssh connection is kept open, so the passphrase is asked once.
INTERVAL=${INTERVAL:-30}
HOST=${HOST:-gmo}
PART=${PART:-part-group_1a6e94}
TEAM_GPUS=${TEAM_GPUS:-4}
TEAM_CPUS=${TEAM_CPUS:-64}
OUT=${OUT:-$HOME/gpu_status.html}
HIST=${HIST:-$HOME/.gpu_watch_history}
NAMES=${NAMES:-$HOME/.gpu_watch_names}
RTX_HOST=${RTX_HOST-rtx}
THEME=${THEME:-eva}   # eva = 黒とオレンジの警告パネル風 / plain = 前の見た目
CP="$HOME/.ssh/cm-gpuwatch-%r@%h:%p"
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CP" -o ControlPersist=10m -o ConnectTimeout=15 "$HOST")
SSHR=(ssh -o ControlMaster=auto -o ControlPath="$CP" -o ControlPersist=10m -o ConnectTimeout=10 "$RTX_HOST")

"${SSH[@]}" true || { echo "ssh $HOST failed"; exit 1; }
ME=$("${SSH[@]}" 'echo $USER')
if [ -n "$RTX_HOST" ]; then "${SSHR[@]}" true || echo "ssh $RTX_HOST failed: RTX は OFFLINE と表示します（RTX_HOST= で非表示）"; fi
trap '"${SSH[@]}" -O exit >/dev/null 2>&1; [ -n "$RTX_HOST" ] && "${SSHR[@]}" -O exit >/dev/null 2>&1; rm -f "$TASKF" "$RTXF" "$RTXF.err"; echo; echo stopped; exit 0' INT TERM
touch "$HIST" "$NAMES"

EVA_CSS=$(cat <<'CSS'
:root{--o:#ff8a00;--r:#ff2a1a;--g:#3dff6e;--bg:#050505;--dim:#5a3a12;--txt:#ffd9a8;--sub:#b07a40;--m:"Hiragino Mincho ProN","Yu Mincho","YuMincho","Noto Serif JP",serif;--d:"DIN Condensed","DIN Alternate","Bahnschrift","Arial Narrow",sans-serif;--s:"Hiragino Sans","Yu Gothic",sans-serif}
*{box-sizing:border-box}html{background:var(--bg)}
body{margin:0;min-height:100vh;color:var(--txt);font-family:var(--d);background:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='56' height='100'><path d='M28 66L0 50L0 16L28 0L56 16L56 50L28 66L28 100' fill='none' stroke='%23ff8a00' stroke-opacity='.08'/></svg>"),radial-gradient(900px 500px at 85% -10%,#2a1200 0,transparent 70%),var(--bg)}
body::after{content:"";position:fixed;inset:0;pointer-events:none;background:repeating-linear-gradient(0deg,rgba(0,0,0,.3) 0 1px,transparent 1px 3px)}
.tape{height:14px;background:repeating-linear-gradient(-45deg,var(--o) 0 14px,#000 14px 28px)}
.wrap{padding:20px 28px 24px}
.en{font-family:var(--d);letter-spacing:.2em;font-size:13px;color:var(--o);text-transform:uppercase}
header{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:2px solid var(--o);padding-bottom:12px;margin-bottom:16px}
h1{font-family:var(--m);font-weight:900;font-size:60px;margin:4px 0;color:#fff;transform:scaleX(.8);transform-origin:left;letter-spacing:-.02em;line-height:1;text-shadow:0 0 22px rgba(255,138,0,.45)}
.clock{text-align:right}.clock b{display:block;font-size:56px;line-height:1;color:var(--o);font-weight:700;font-variant-numeric:tabular-nums;text-shadow:0 0 14px rgba(255,138,0,.7)}
.alert{display:flex;align-items:baseline;gap:20px;padding:10px 18px;margin-bottom:16px;border:2px solid var(--o)}
.alert b{font-family:var(--m);font-weight:900;font-size:32px;color:#fff;transform:scaleX(.85);transform-origin:left;display:inline-block}
.alert span{letter-spacing:.2em;font-size:15px}
.alert.ok{border-color:var(--g);background:linear-gradient(90deg,rgba(61,255,110,.16),transparent 70%)}.alert.ok span{color:var(--g)}
.alert.red{border-color:var(--r);background:repeating-linear-gradient(-45deg,rgba(255,42,26,.24) 0 16px,rgba(255,42,26,.08) 16px 32px)}.alert.red b{color:var(--r);text-shadow:0 0 14px var(--r)}.alert.red span{color:var(--r)}
.blink{animation:bl 1.1s steps(2,start) infinite}@keyframes bl{to{visibility:hidden}}
.grid{display:grid;grid-template-columns:270px 1fr;gap:16px;margin-bottom:16px}
.panel{border:1px solid var(--dim);background:rgba(10,6,2,.85)}
.ph{background:var(--o);color:#000;font-family:var(--m);font-weight:900;font-size:15px;padding:4px 12px;letter-spacing:.05em}.ph i{font-style:normal;font-family:var(--d);letter-spacing:.22em;font-size:12px;margin-left:10px;opacity:.7}
.core svg{width:100%;max-width:230px;display:block;margin:14px auto 0}
.hx0{fill:rgba(255,138,0,.05);stroke:#2a1a08;stroke-width:12}
.hx1{fill:none;stroke:var(--o);stroke-width:12;filter:drop-shadow(0 0 6px var(--o))}.hx1.full{stroke:var(--r);filter:drop-shadow(0 0 8px var(--r))}
.big{font-family:var(--d);font-size:88px;fill:#fff;text-anchor:middle;font-weight:700}.of{font-size:42px;fill:var(--o)}.lab{font-family:var(--d);fill:var(--o);text-anchor:middle;font-size:20px;letter-spacing:.2em}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--dim);margin:12px;border:1px solid var(--dim)}.stats div{background:#0a0602;text-align:center;padding:6px 2px}.stats b{display:block;font-size:32px;color:var(--o);font-weight:700}.stats span{font-size:11px;letter-spacing:.1em;color:var(--sub);font-family:var(--s)}
.cpu{margin:0 12px 12px;border:1px solid var(--dim);padding:8px 10px;background:#0a0602}.cl{display:flex;align-items:baseline;gap:8px}.cl span{font-family:var(--m);font-weight:900;font-size:13px;color:var(--txt)}.cl b{font-size:28px;color:var(--o);font-weight:700;margin-left:auto}.cl b small{font-size:16px;color:var(--sub)}.cl em{font-style:normal;font-size:20px;color:var(--o);min-width:52px;text-align:right}.cpu.hot .cl b,.cpu.hot .cl em{color:var(--r)}
.cells{display:grid;grid-template-columns:repeat(16,1fr);gap:2px;margin-top:6px}.cells i{height:9px;background:#2a1a08}.cells i.on{background:var(--o);box-shadow:0 0 4px var(--o)}.cells i.me{background:var(--g);box-shadow:0 0 4px var(--g)}.cpu.hot .cells i.on{background:var(--r);box-shadow:0 0 4px var(--r)}
.slots{display:grid;gap:12px;padding:12px}
.slot{--bc:var(--o);--cut:polygon(0 0,calc(100% - 22px) 0,100% 22px,100% 100%,22px 100%,0 calc(100% - 22px));clip-path:var(--cut);background:var(--bc);padding:2px;min-height:230px}
.slot .in{clip-path:var(--cut);height:100%;padding:12px 14px 14px;display:flex;flex-direction:column;gap:3px;background:linear-gradient(170deg,color-mix(in srgb,var(--bc) 22%,transparent),transparent 62%),#070401}
.slot.me{--bc:var(--g)}.slot.warn{--bc:var(--r)}.slot.warn .tl b{animation:bl 1.1s steps(2,start) infinite}
.slot.free{--bc:#3a2a14}.slot.free .in{background:repeating-linear-gradient(-45deg,#0a0703 0 10px,#0e0a05 10px 20px)}
.top{display:flex;justify-content:space-between;align-items:center;font-size:17px;letter-spacing:.16em;color:var(--bc)}
.st{font-family:var(--m);font-weight:900;font-size:13px;letter-spacing:.1em;padding:1px 8px;background:var(--bc);color:#000}
.slot.free .top{color:#7a5a30}.slot.free .st{background:none;color:#7a5a30;border:1px solid #3a2a14}
.jid{font-size:13px;letter-spacing:.16em;color:var(--sub)}
.name{font-family:var(--m);font-weight:900;font-size:22px;color:#fff;line-height:1.15;word-break:break-all;margin-top:2px}
.user{font-size:13px;font-family:var(--s);color:var(--txt)}
.u{display:inline-block;width:8px;height:8px;margin-right:7px;background:hsl(var(--h) 80% 60%);transform:rotate(45deg)}
.tl{margin-top:auto;padding-top:6px}.tl span{display:block;font-size:11px;letter-spacing:.14em;color:var(--sub);font-family:var(--s)}.tl b{font-size:42px;line-height:1;color:var(--bc);font-weight:700;font-variant-numeric:tabular-nums;text-shadow:0 0 10px var(--bc)}
.seg{height:8px;background:repeating-linear-gradient(90deg,#2a1a08 0 6px,transparent 6px 8px);margin-top:4px}.seg i{display:block;height:100%;background:repeating-linear-gradient(90deg,var(--bc) 0 6px,transparent 6px 8px)}
.meta{display:flex;justify-content:space-between;gap:6px;font-size:12px;color:var(--sub);font-family:var(--s);margin-top:3px}
.idle{margin:auto 0;text-align:center;font-size:36px;letter-spacing:.3em;color:#4a3518}
.two{display:grid;grid-template-columns:1fr 1fr;gap:16px}.pb{padding:6px 12px 12px}
.spark{display:block;width:100%;height:120px}
table{width:100%;border-collapse:collapse;font-size:13px;font-family:var(--s)}th{font-family:var(--d);letter-spacing:.16em;color:var(--o);font-weight:400;text-align:left;font-size:13px;border-bottom:1px solid var(--o);padding:7px 8px}td{padding:7px 8px;border-bottom:1px solid #2a1a08}tr.me td{color:var(--g)}
.chip{display:inline-block;padding:1px 8px;font-size:12px;border:1px solid var(--c);color:var(--c);background:color-mix(in srgb,var(--c) 15%,transparent)}
.empty{padding:16px 4px;color:#7a5a30;letter-spacing:.16em}
.foot{margin-top:14px;font-size:12px;color:var(--sub);font-family:var(--s);line-height:2}
@media(max-width:900px){.grid,.two{grid-template-columns:1fr}.slots{grid-template-columns:repeat(2,1fr)!important}h1{font-size:44px}}
.grid{grid-template-columns:360px 1fr}
.gauges{display:grid;grid-template-columns:1fr 1fr;gap:4px;padding:10px 10px 0}.hg svg{width:100%;display:block;margin:0}
.hg .lab{font-size:19px}.hg .big{font-size:80px}.hg .big.sm{font-size:62px}
.cpu{margin:8px 12px 0}.cl em{font-size:12px;color:var(--sub);font-family:var(--s);min-width:0}.cells i.co{background:#b48cff;box-shadow:0 0 4px #b48cff}
.sw{display:inline-block;width:9px;height:9px;margin:0 4px 0 6px;vertical-align:-1px;background:#2a1a08}.sw.on{background:var(--o)}.sw.co{background:#b48cff}.sw.me{background:var(--g)}
.stats{grid-template-columns:repeat(4,1fr)}.stats b{font-size:28px}
.lbl{display:flex;align-items:baseline;gap:12px;margin:12px 12px 0;padding-bottom:4px;border-bottom:1px dashed var(--dim)}.lbl b{font-family:var(--m);font-weight:900;font-size:15px;color:var(--o)}.lbl span{font-size:14px;letter-spacing:.12em;color:var(--sub)}.lbl.co b{color:#b48cff}
.minis{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px;padding:12px}
.slot.mini{--bc:#b48cff;--cut:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,14px 100%,0 calc(100% - 14px));min-height:0}.slot.mini.me{--bc:var(--g)}.slot.mini.warn{--bc:var(--r)}
.slot.mini .in{padding:8px 12px 10px}.slot.mini .name{font-size:17px}.slot.mini .tl b{font-size:28px}.slot.mini .top{font-size:14px}
.empty{padding:12px 16px}
.zone{--zc:var(--o);position:relative;border:2px solid var(--zc);padding:0 14px 14px;margin-bottom:20px;background:linear-gradient(180deg,color-mix(in srgb,var(--zc) 7%,transparent),transparent 240px);overflow:hidden}
.zone.rx{--zc:#31e6ff}.zone>*{position:relative;z-index:1}
.zone::after{content:attr(data-w);position:absolute;right:18px;bottom:-34px;font-family:var(--d);font-weight:700;font-size:190px;line-height:1;color:var(--zc);opacity:.07;pointer-events:none;z-index:0}
.zh{display:flex;align-items:center;gap:16px;margin:0 -14px 14px;padding:4px 16px;background:var(--zc);color:#000}.zh b{font-family:var(--d);font-size:38px;line-height:1.1;letter-spacing:.06em}.zh span{font-family:var(--m);font-weight:900;font-size:15px}.zh em{margin-left:auto;font-style:normal;font-family:var(--d);letter-spacing:.2em;font-size:15px}
.zone .grid{margin-bottom:14px}.zone.rx .rtx{margin:0}.zone.rx .rtx .ph{background:#31e6ff}
.mk{font-style:normal;display:inline-block;background:var(--o);color:#000;font-family:var(--d);font-weight:700;letter-spacing:.06em;font-size:13px;padding:0 5px;margin-right:7px;line-height:1.35}.mk.rx{background:#31e6ff}
.alerts{display:grid;grid-template-columns:2fr 1fr;gap:12px;margin-bottom:16px}.alerts.one{grid-template-columns:1fr}.alerts .alert{margin:0;align-items:center}
.ak{font-style:normal;font-family:var(--d);font-weight:700;font-size:22px;letter-spacing:.06em;padding:0 8px;background:var(--o);color:#000}.ak.rx{background:#31e6ff}
.alert.rxb{border-color:#31e6ff;background:linear-gradient(90deg,rgba(49,230,255,.16),transparent 70%)}.alert.rxb span{color:#31e6ff}
.hist{margin-bottom:6px}
.top{letter-spacing:.06em;gap:6px}.top span{white-space:nowrap}.st{white-space:nowrap}.alert b{white-space:nowrap}.alerts .alert span{letter-spacing:.12em}
.rtx{--x:#31e6ff;margin-bottom:16px;border-color:#124a55}.rtx .ph{background:var(--x)}.rtx .hx1{stroke:var(--x);filter:drop-shadow(0 0 6px var(--x))}.rtx .hx1.full{stroke:var(--r)}.rtx .lab{fill:var(--x);font-size:17px}
.rgrid{display:grid;grid-template-columns:190px 300px 1fr;gap:16px;padding:12px;align-items:start}.rgrid .hg svg{max-width:190px}
.meter{--bc:var(--x);margin-bottom:9px}.meter.hot{--bc:var(--r)}.mh{display:flex;justify-content:space-between;align-items:baseline;font-size:12px;color:var(--sub);font-family:var(--s)}.mh b{font-family:var(--d);font-size:21px;color:#fff;font-weight:700}
.rprocs{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px}.slot.rp{--bc:var(--x)}.slot.rp.me{--bc:var(--g)}.slot.rp.free{--bc:#123a42}.slot.rp.free .top,.slot.rp.free .idle{color:#1d5a66}.slot.rp .name .u{margin-right:8px}
.cmd{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:var(--sub);word-break:break-all;line-height:1.35;max-height:2.8em;overflow:hidden}
.rtag{font-style:normal;margin-left:auto;font-family:var(--m);font-weight:900;font-size:16px;padding:2px 12px;border:1px solid #31e6ff;color:#31e6ff}.rtag.busy{background:#31e6ff;color:#000}.rtag.off{border-color:var(--r);color:var(--r)}
.sw.rx{background:#31e6ff}
@media(max-width:1100px){.rgrid{grid-template-columns:1fr 1fr}.rprocs{grid-column:1/-1}}
@media(max-width:1000px){.grid,.two{grid-template-columns:1fr}.slots{grid-template-columns:repeat(2,1fr)!important}}
CSS
)
EVA_JS=$(cat <<'JS'
const c=document.getElementById("cd"),T=[...document.querySelectorAll("[data-rem]")];
const f=x=>{x=Math.max(0,x);const p=n=>String(n).padStart(2,"0");return p(Math.floor(x/3600))+":"+p(Math.floor(x%3600/60))+":"+p(x%60)};
setInterval(()=>{s--;if(s<=0){location.reload();return}c.textContent=s;T.forEach(t=>{const v=+t.dataset.rem+(t.dataset.up?1:-1);t.dataset.rem=v;t.textContent=f(v)})},1000)
JS
)

render() {
  local data="$1" now="$2" err="$3" epoch
  epoch=$(date +%s)
  # Multi-line text (CSS, JS, ssh errors) goes through the environment: macOS awk rejects newlines in -v.
  echo "$data" | ECSS="$EVA_CSS" EJS="$EVA_JS" GW_ERR="$err" RTX_ON="${RTX_HOST:+1}" RTX_ERR="$rtx_err" awk -F'|' -v me="$ME" -v total="$TEAM_GPUS" -v now="$now" -v epoch="$epoch" \
      -v interval="$INTERVAL" -v part="$PART" -v hist="$HIST" -v names="$NAMES" -v taskf="$TASKF" -v theme="$THEME" -v tcpu="$TEAM_CPUS" -v rtxf="$RTXF" -v host="$HOST" -v rhost="$RTX_HOST" '
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
    function hms(s){ if (s<0) s=0; return sprintf("%02d:%02d:%02d", int(s/3600), int((s%3600)/60), s%60) }
    function hexg(v,tot,lab,   p){
      p=(tot>0? v/tot : 0); if (p>1) p=1
      hexr(p, sprintf("%s %d%%", lab, p*100), v, "/ " tot)
    }
    function hexr(p,top,big,bot,   c){
      c=(p>=.9?" full":"")
      printf "<div class=\"hg\"><svg viewBox=\"0 0 200 200\"><polygon points=\"100,10 180,56 180,144 100,190 20,144 20,56\" class=\"hx0\"/>"
      printf "<polygon points=\"100,10 180,56 180,144 100,190 20,144 20,56\" class=\"hx1%s\" style=\"stroke-dasharray:%.1f 600\"/>", c, 553*p
      printf "<text x=\"100\" y=\"60\" class=\"lab\">%s</text><text x=\"100\" y=\"124\" class=\"big%s\">%s</text><text x=\"100\" y=\"154\" class=\"lab\">%s</text></svg></div>", top, (length(big "")>2?" sm":""), big, bot
    }
    function card(i,cls,label,   lim,frac,title,sub2){
      lim=R_l[i]; frac=(lim>0? R_t[i]/lim : 0); if (frac>1) frac=1
      title=(R_task[i]!="" ? R_task[i] : R_n[i]); sub2=(R_task[i]!="" ? who(R_u[i]) " · " R_n[i] : who(R_u[i]))
      cls=cls (R_u[i]==me?" me":"") (frac>.85?" warn":"")
      printf "<div class=\"%s\"><div class=\"in\"><div class=\"top\"><span>%s</span><span class=\"st\">稼働中</span></div>", cls, label
      printf "<div class=\"jid\">JOB #%s</div><div class=\"name\">%s</div><div class=\"user\"><i class=\"u\" style=\"--h:%d\"></i>%s</div>", e(R_id[i]), e(title), hue(R_u[i]), e(sub2)
      if (lim>0) printf "<div class=\"tl\"><span>残り時間</span><b data-rem=\"%d\">%s</b></div>", lim-R_t[i], hms(lim-R_t[i])
      else printf "<div class=\"tl\"><span>経過時間</span><b data-rem=\"%d\" data-up=\"1\">%s</b></div>", R_t[i], hms(R_t[i])
      printf "<div class=\"seg\"><i style=\"width:%d%%\"></i></div><div class=\"meta\"><span>%s コア · %s</span><span>%s</span></div></div></div>\n", frac*100, R_c[i], e(R_m[i]), (lim>0? "上限 " hm(lim) : "")
    }
    function meter(lab,val,frac,hot){
      if (frac<0) frac=0; if (frac>1) frac=1
      printf "<div class=\"meter%s\"><div class=\"mh\"><span>%s</span><b>%s</b></div><div class=\"seg\"><i style=\"width:%d%%\"></i></div></div>", (hot?" hot":""), lab, val, frac*100
    }
    function rtxtag(){
      if (!rtx_on) return ""
      if (!rtx_ok) return "<em class=\"rtag off\">RTX 通信途絶</em>"
      return (rn? "<em class=\"rtag busy\">RTX 使用中 " rn "</em>" : "<em class=\"rtag\">RTX 空き</em>")
    }
    function rtxpanel(   i){
      print "<div class=\"panel rtx\"><div class=\"ph\">■ GPU とプロセス<i>nvidia-smi</i></div>"
      if (!rtx_ok) { print "<div class=\"alert red\" style=\"margin:12px\"><b class=\"blink\">通信途絶</b><span>RTX OFFLINE — " e(rtx_err) "</span></div></div>"; return }
      print "<div class=\"rgrid\"><div>"
      hexr(RU/100, "GPU 使用率", RU "%", (rn? rn " プロセス" : "空き"))
      print "</div><div class=\"meters\">"
      meter("VRAM", sprintf("%.1f / %.0f GB", RMU/1024, RMT/1024), (RMT>0? RMU/RMT : 0), (RMT>0 && RMU/RMT>=.9))
      meter("温度", RT " ℃", RT/100, RT>=85)
      meter("電力", sprintf("%.0f / %.0f W", RP, RPL), (RPL>0? RP/RPL : 0), (RPL>0 && RP/RPL>=.95))
      if (RNC>0) meter("VM の CPU 負荷", sprintf("%.1f / %d", RLD, RNC), RLD/RNC, RLD/RNC>=.9)
      if (RRT>0) meter("VM のメモリ", sprintf("%.0f / %.0f GB", RRU/1024, RRT/1024), RRU/RRT, RRU/RRT>=.9)
      printf "<div class=\"meta\"><span>%s</span></div></div><div class=\"rprocs\">", e(RG)
      if (!rn) print "<div class=\"slot mini rp free\"><div class=\"in\"><div class=\"top\"><span><em class=\"mk rx\">RTX</em>GPU</span><span class=\"st\">待機</span></div><div class=\"idle\">STANDBY</div><div class=\"meta\"><span>GPU を使っているプロセスはありません</span></div></div></div>"
      for (i=1;i<=rn;i++) {
        printf "<div class=\"slot mini rp%s\"><div class=\"in\"><div class=\"top\"><span><em class=\"mk rx\">RTX</em>PID %s</span><span class=\"st\">使用中</span></div>", (RPU[i]==rme?" me":""), e(RPID[i])
        printf "<div class=\"name\"><i class=\"u\" style=\"--h:%d\"></i>%s</div><div class=\"cmd\">%s</div>", hue(RPU[i]), e(who(RPU[i])), e(RPC[i])
        printf "<div class=\"tl\"><span>経過時間</span><b data-rem=\"%d\" data-up=\"1\">%s</b></div>", RPT[i], hms(RPT[i])
        printf "<div class=\"seg\"><i style=\"width:%d%%\"></i></div><div class=\"meta\"><span>VRAM %.1f GB</span><span>%d%%</span></div></div></div>\n", (RMT>0? RPM[i]*100/RMT : 0), RPM[i]/1024, (RMT>0? RPM[i]*100/RMT : 0)
      }
      print "</div></div></div>"
    }
    function eva(   i,j,s,n0,cnt,W,H,pts,cpts,x,y,py,k,mins,nc,cc,cfree){
      cfree=(tcpu-cu>0? tcpu-cu : 0)
      print "<!DOCTYPE html><html lang=\"ja\"><head><meta charset=\"utf-8\">"
      print "<meta http-equiv=\"refresh\" content=\"" interval+15 "\"><title>GPU " used+0 "/" total " CPU " cu+0 "/" tcpu " · VIKING</title><style>" ecss "</style></head><body>"
      print "<div class=\"tape\"></div><div class=\"wrap\">"
      print "<header><div><div class=\"en\">Team VIKING // Compute node status // " e(part) "</div><h1>計算資源稼働状況</h1><div class=\"en\">Operator: " e(who(me)) "</div></div>"
      print "<div class=\"clock\"><div class=\"en\">Last sync</div><b>" now "</b><div class=\"en\">Next sync <span id=\"cd\">" interval "</span> sec</div></div></header>"
      print "<div class=\"alerts" (rtx_on?"":" one") "\">"
      if (err!="") print "<div class=\"alert red\"><i class=\"ak\">B300</i><b class=\"blink\">通信途絶</b><span>" e(err) "</span></div>"
      else if (free==0) printf "<div class=\"alert red\"><i class=\"ak\">B300</i><b class=\"blink\">空きGPUなし</b><span>%d JOB(S) WAITING · CPU %d CORES FREE</span></div>\n", np, cfree
      else printf "<div class=\"alert ok\"><i class=\"ak\">B300</i><b>空き %d 基 ・ CPU %d コア</b><span>STANDING BY</span></div>\n", free, cfree
      if (rtx_on) {
        if (!rtx_ok) print "<div class=\"alert red\"><i class=\"ak rx\">RTX</i><b class=\"blink\">通信途絶</b><span>OFFLINE</span></div>"
        else if (rn) printf "<div class=\"alert rxb\"><i class=\"ak rx\">RTX</i><b>使用中 %d</b><span>GPU %d%% · VRAM %.0f/%.0f GB</span></div>\n", rn, RU, RMU/1024, RMT/1024
        else print "<div class=\"alert ok\"><i class=\"ak rx\">RTX</i><b>空き</b><span>STANDING BY</span></div>" }
      print "</div>"
      # ---- row 1: resources | running jobs
      printf "<section class=\"zone b3\" data-w=\"B300\"><div class=\"zh\"><b>B300</b><span>Slurm クラスタ ・ GPU %d 基 ・ CPU %d コア ・ sbatch / srun で使う</span><em>ssh %s</em></div>\n", total, tcpu, e(host)
      print "<div class=\"grid\"><div class=\"panel res\"><div class=\"ph\">■ 資源<i>" e(part) "</i></div><div class=\"gauges\">"
      hexg(used+0, total, "B300"); hexg(cu+0, tcpu, "CPU")
      printf "</div><div class=\"cpu%s\"><div class=\"cl\"><span>CPU コア割り当て</span><em>1 マス = 1 コア</em></div><div class=\"cells\">", (tcpu>0 && cu/tcpu>=.9?" hot":"")
      k=0; for (i=1;i<=nr;i++) for (j=1;j<=R_c[i]+0 && k<tcpu;j++) { k++; printf "<i class=\"%s\"></i>", (R_u[i]==me?"me":(R_g[i]==0?"co":"on")) }
      while (k<tcpu) { k++; printf "<i></i>" }
      printf "</div><div class=\"meta\"><span><i class=\"sw on\"></i>GPU ジョブ <i class=\"sw co\"></i>CPU のみ <i class=\"sw me\"></i>自分</span><span>自分 %d コア</span></div></div>\n", cme
      printf "<div class=\"stats\"><div><b>%d</b><span>空き GPU</span></div><div><b>%d</b><span>空き CPU</span></div><div><b>%d</b><span>実行中</span></div><div><b>%d</b><span>待ち</span></div></div></div>\n", free, cfree, nr, np
      print "<div class=\"panel\"><div class=\"ph\">■ 稼働中のジョブ<i>Running</i></div>"
      printf "<div class=\"lbl\"><b>GPU ユニット</b><span>%d / %d 基使用</span></div><div class=\"slots\" style=\"grid-template-columns:repeat(%d,1fr)\">\n", used, total, total
      s=0
      for (i=1;i<=nr;i++) for (j=1;j<=R_g[i] && s<total;j++) { s++; card(i, "slot busy", sprintf("<em class=\"mk\">B300</em>GPU-%02d", s)) }
      while (s<total) { s++; printf "<div class=\"slot free\"><div class=\"in\"><div class=\"top\"><span><em class=\"mk\">B300</em>GPU-%02d</span><span class=\"st\">待機</span></div><div class=\"idle\">STANDBY</div><div class=\"meta\"><span>いつでも使えます</span></div></div></div>\n", s }
      print "</div>"
      nc=0; cc=0; for (i=1;i<=nr;i++) if (R_g[i]==0) { nc++; cc+=R_c[i] }
      printf "<div class=\"lbl co\"><b>CPU のみ</b><span>%d 件 · %d コア</span></div>", nc, cc
      if (nc) { print "<div class=\"minis\">"; for (i=1;i<=nr;i++) if (R_g[i]==0) card(i, "slot mini", "<em class=\"mk\">B300</em>CPU ONLY"); print "</div>" }
      else print "<div class=\"empty\">NO CPU-ONLY JOBS — なし</div>"
      print "</div></div>"
      print "<div class=\"panel\"><div class=\"ph\">■ 待機ジョブ<i>Pending queue</i></div><div class=\"pb\">"
      if (np) { print "<table><tr><th>JOB</th><th>USER</th><th>NAME</th><th>GPU</th><th>CPU</th><th>MEM</th><th>REASON</th></tr>"
        for (i=1;i<=np;i++) printf "<tr%s><td>%s</td><td><i class=\"u\" style=\"--h:%d\"></i>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", (P_u[i]==me?" class=\"me\"":""), e(P_id[i]), hue(P_u[i]), e(who(P_u[i])), e(P_n[i]), (P_g[i]>0? P_g[i] : "—"), P_c[i], e(P_m[i]), chip(P_r[i])
        print "</table>" } else print "<div class=\"empty\">NO PENDING JOBS — 待ちなし</div>"
      print "</div></div></section>"
      if (rtx_on) { printf "<section class=\"zone rx\" data-w=\"RTX\"><div class=\"zh\"><b>RTX PRO 6000</b><span>チーム専用 VM ・ GPU 1 基 ・ Slurm なし（使う前に声かけ）</span><em>ssh %s</em></div>\n", e(rhost); rtxpanel(); print "</section>" }
      # ---- row 2: history | pending
      print "<div class=\"hist\"><div class=\"panel\"><div class=\"ph\">■ 稼働履歴<i>Load history</i></div><div class=\"pb\">"
      n0=(nh>240? nh-239 : 1); cnt=nh-n0+1
      if (cnt>=2) {
        W=600; H=130; pts=""; cpts=""; rpts=""
        for (i=n0;i<=nh;i++) { x=(i-n0)*W/(cnt-1); y=H-6-(HU[i]/total)*(H-12); if (i>n0) pts=pts sprintf("%.1f,%.1f ",x,py); pts=pts sprintf("%.1f,%.1f ",x,y); py=y
          if (HC[i]>=0 && tcpu>0) cpts=cpts sprintf("%.1f,%.1f ", x, H-6-(HC[i]>tcpu?1:HC[i]/tcpu)*(H-12))
          if (HR[i]>=0) rpts=rpts sprintf("%.1f,%.1f ", x, H-6-(HR[i]>100?1:HR[i]/100)*(H-12)) }
        printf "<svg class=\"spark\" viewBox=\"0 0 %d %d\" preserveAspectRatio=\"none\"><defs><linearGradient id=\"g\" x1=\"0\" x2=\"0\" y1=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#ff8a00\" stop-opacity=\".4\"/><stop offset=\"1\" stop-color=\"#ff8a00\" stop-opacity=\"0\"/></linearGradient></defs>", W, H
        for (k=0;k<=4;k++) printf "<line x1=\"0\" x2=\"%d\" y1=\"%.1f\" y2=\"%.1f\" stroke=\"%s\" stroke-dasharray=\"2 5\"/>", W, H-6-(k/4)*(H-12), H-6-(k/4)*(H-12), (k==4?"#ff2a1a66":"#5a3a12")
        printf "<polygon points=\"0,%d %s%d,%d\" fill=\"url(#g)\"/><polyline points=\"%s\" fill=\"none\" stroke=\"#ff8a00\" stroke-width=\"2.5\" vector-effect=\"non-scaling-stroke\"/>", H, pts, W, H, pts
        if (cpts!="") printf "<polyline points=\"%s\" fill=\"none\" stroke=\"#b48cff\" stroke-width=\"2\" stroke-dasharray=\"6 3\" vector-effect=\"non-scaling-stroke\"/>", cpts
        if (rpts!="") printf "<polyline points=\"%s\" fill=\"none\" stroke=\"#31e6ff\" stroke-width=\"1.5\" stroke-dasharray=\"2 3\" vector-effect=\"non-scaling-stroke\"/>", rpts
        print "</svg>"
        mins=int((HT[nh]-HT[n0])/60); printf "<div class=\"meta\"><span>%d 分前</span><span><i class=\"sw on\"></i>B300（%d 基）　<i class=\"sw co\"></i>CPU（%d コア）%s　赤線 = 満杯</span><span>現在</span></div>", mins, total, tcpu, (rtx_on? "　<i class=\"sw rx\"></i>RTX 使用率" : "")
      } else print "<div class=\"empty\">DATA COLLECTING — 2 回目の更新から表示</div>"
      print "</div></div></div>"
      print "<div class=\"foot\">機械：<b style=\"color:#ff8a00\">橙の囲み・B300 の札</b> = B300（Slurm）　<b style=\"color:#31e6ff\">水色の囲み・RTX の札</b> = RTX PRO 6000<br>枠の色：<b style=\"color:#ff8a00\">橙</b> = 稼働中　<b style=\"color:#3dff6e\">緑</b> = 自分のジョブ　<b style=\"color:#ff2a1a\">赤</b> = 上限時間の 85% を超えた（点滅）・ CPU は割り当てられたコア数（実際の負荷ではありません）<br>理由の色：<span class=\"chip\" style=\"--c:#f59e0b\">GPU 上限</span> <span class=\"chip\" style=\"--c:#f97316\">CPU 上限</span> <span class=\"chip\" style=\"--c:#ef4444\">メモリ上限</span> <span class=\"chip\" style=\"--c:#8b5cf6\">前のジョブ待ち</span> <span class=\"chip\" style=\"--c:#06b6d4\">配列の同時実行数</span></div>"
      print "</div><div class=\"tape\"></div><script>let s=" interval ";" ejs "</script></body></html>"
    }
    BEGIN { ecss=ENVIRON["ECSS"]; ejs=ENVIRON["EJS"]; err=ENVIRON["GW_ERR"]
            while ((getline line < names) > 0) { split(line,a," "); if (a[1]!="") { sub(/^[^ ]+ +/,"",line); alias[a[1]]=line } }
            while ((getline line < taskf) > 0) { split(line,a,"|"); if (a[1]!="") TK[a[1]]=a[2] }
            rtx_on=(ENVIRON["RTX_ON"]!=""); rtx_err=ENVIRON["RTX_ERR"]; rn=0
            if (rtx_on) while ((getline line < rtxf) > 0) {
              if (line ~ /^@@ME /) rme=substr(line,6)
              else if (line ~ /^@@GPU /) { split(substr(line,7),b,", *"); RG=b[1]; RU=b[2]+0; RMU=b[3]+0; RMT=b[4]+0; RT=b[5]+0; RP=b[6]+0; RPL=b[7]+0 }
              else if (line ~ /^@@SYS /) { split(substr(line,7),b," "); RNC=b[1]+0; RLD=b[2]+0; RRU=b[3]+0; RRT=b[4]+0 }
              else if (line ~ /^@@P /) { split(substr(line,5),b,"|"); rn++; RPID[rn]=b[1]; RPU[rn]=b[2]; RPT[rn]=b[3]+0; RPM[rn]=b[4]+0; RPC[rn]=b[5] } }
            rtx_ok=(rtx_on && RG!="")
            if (rtx_on && !rtx_ok && rtx_err=="") rtx_err="nvidia-smi の出力がありません" }
    NF>=9 {
      for (k=1;k<=NF;k++) gsub(/^ +| +$/,"",$k)
      g=gpus($6)
      if ($4=="RUNNING") {
        nr++; R_id[nr]=$1; R_u[nr]=$2; R_n[nr]=$3; R_g[nr]=g; R_t[nr]=secs($5); R_l[nr]=secs($10); R_c[nr]=$7; R_m[nr]=$8
        R_task[nr]=(($11 in TK) ? TK[$11] : "")
        used+=g; if ($2==me) mine+=g
        cu+=$7; if ($2==me) cme+=$7
      } else { np++; P_id[np]=$1; P_u[np]=$2; P_n[np]=$3; P_g[np]=g; P_r[np]=$9; P_c[np]=$7; P_m[np]=$8 }
    }
    END {
      if (err=="") { print epoch, used+0, cu+0, (rtx_ok? RU : -1) >> hist; close(hist) }
      nh=0; while ((getline line < hist) > 0) { split(line,a," "); nh++; HT[nh]=a[1]; HU[nh]=a[2]; HC[nh]=(a[3]==""? -1 : a[3]+0); HR[nh]=(a[4]==""? -1 : a[4]+0) }
      free=total-used; if (free<0) free=0
      if (theme=="eva") { eva(); exit }
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
      print ".slot .gpu{font-size:11px;color:var(--sub);letter-spacing:.1em;display:flex;justify-content:space-between}.slot .jid{letter-spacing:0;font-family:ui-monospace,Menlo,monospace;color:#c7d2fe}.spec{display:flex;gap:6px;margin-top:8px}.spec span{font-size:11px;padding:2px 8px;border-radius:6px;background:#0b1224;color:#c7d2fe;border:1px solid var(--line)}.slot .name{font-size:16px;font-weight:700;margin:6px 0 2px;word-break:break-all}.slot .user{font-size:13px;color:hsl(var(--h) 80% 75%)}.slot.free .name{color:#56628a;font-weight:600}"
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
      printf "<div class=\"stats\"><div class=\"stat\"><b>%d</b><span>空き GPU</span></div><div class=\"stat\"><b>%d</b><span>走っている</span></div><div class=\"stat\"><b>%d</b><span>待っている</span></div></div><div class=\"stats\"><div class=\"stat\"><b>%d/%d</b><span>CPU コア（%d%%）</span></div></div></div>\n", free, nr, np, cu, tcpu, (tcpu>0? cu*100/tcpu : 0)
      print "<div class=\"card\"><h2>GPU スロット</h2><div class=\"slots\">"
      s=0
      for (i=1;i<=nr;i++) for (j=1;j<=R_g[i] && s<total;j++) { s++
        h=hue(R_u[i]); lim=R_l[i]; frac=(lim>0? R_t[i]/lim : 0); if (frac>1) frac=1
        title=(R_task[i]!="" ? R_task[i] : R_n[i]); sub2=(R_task[i]!="" ? who(R_u[i]) " · " R_n[i] : who(R_u[i]))
        printf "<div class=\"slot busy%s\" style=\"--h:%d\"><div><div class=\"gpu\"><span>GPU %d</span><span class=\"jid\">#%s</span></div><div class=\"name\">%s</div><div class=\"user\">%s</div>", (R_u[i]==me?" me":""), h, s, e(R_id[i]), e(title), e(sub2)
        printf "<div class=\"spec\"><span>%s コア</span><span>%s</span></div></div>", R_c[i], e(R_m[i])
        printf "<div><div class=\"bar\"><i class=\"%s\" style=\"width:%d%%\"></i></div><div class=\"meta\"><span>%s 経過</span><span>%s</span></div></div></div>\n", (frac>.85?"warn":""), frac*100, hm(R_t[i]), (lim>0? "上限 " hm(lim) : "#" e(R_id[i]))
      }
      while (s<total) { s++; printf "<div class=\"slot free\"><div><div class=\"gpu\">GPU %d</div><div class=\"name\">空き</div></div><div class=\"meta\"><span>いつでも使えます</span></div></div>\n", s }
      print "</div></div></div>"
      if (rtx_on) { print "<div class=\"card\" style=\"margin-bottom:18px\"><h2>RTX PRO 6000</h2>"
        if (!rtx_ok) print "<div class=\"err\">取得に失敗しました： " e(rtx_err) "</div>"
        else { printf "<div class=\"sub\">使用率 <b>%d%%</b> ・ VRAM %.1f / %.0f GB ・ %d ℃ ・ %.0f W</div><table><tr><th>PID</th><th>ユーザー</th><th>VRAM</th><th>経過</th><th>コマンド</th></tr>", RU, RMU/1024, RMT/1024, RT, RP
          for (i=1;i<=rn;i++) printf "<tr%s><td>%s</td><td><span class=\"u\" style=\"--h:%d\"></span>%s</td><td>%.1f GB</td><td>%s</td><td>%s</td></tr>", (RPU[i]==rme?" class=\"me\"":""), e(RPID[i]), hue(RPU[i]), e(who(RPU[i])), RPM[i]/1024, hm(RPT[i]), e(RPC[i])
          print "</table>"; if (!rn) print "<div class=\"empty\">GPU を使っているプロセスはありません</div>" }
        print "</div>" }
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
      if (np) { print "<table><tr><th>ジョブ</th><th>ユーザー</th><th>名前</th><th>コア</th><th>メモリ</th><th>理由</th></tr>"
        for (i=1;i<=np;i++) printf "<tr%s><td>%s</td><td><span class=\"u\" style=\"--h:%d\"></span>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", (P_u[i]==me?" class=\"me\"":""), e(P_id[i]), hue(P_u[i]), e(who(P_u[i])), e(P_n[i]), P_c[i], e(P_m[i]), chip(P_r[i])
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

# Runs on the login node: the queue, then "rawjobid|task" read from the first "== <task>" line
# of each running job's log in ~/logs (own jobs; others' only if their logs are readable).
REMOTE=$(cat <<'R'
P=$1
S=$(squeue -p "$P" -h -r -O "JobArrayID:24|,UserName:24|,Name:30|,State:12|,TimeUsed:14|,tres-alloc:100|,NumCPUs:8|,MinMemory:10|,ReasonList:60|,TimeLimit:14|,JobID:16|" 2>/dev/null)
if ! printf '%s\n' "$S" | grep -q '|'; then S=$(squeue -p "$P" -h -r -o '%i|%u|%j|%T|%M|%b|%C|%m|%R|%l|%i') || exit 1; fi
printf '%s\n' "$S"
echo "@@TASKS"
printf '%s\n' "$S" | awk -F'|' '{ for (k=1;k<=NF;k++) gsub(/^ +| +$/,"",$k); if ($4=="RUNNING") print $11 "|" $2 }' |
while IFS='|' read -r j u; do
  f=$(ls /home/"$u"/logs/*-"$j".out 2>/dev/null | head -1)
  [ -n "$f" ] || continue
  task=$(grep -m1 '^== ' "$f" 2>/dev/null | cut -d' ' -f2)
  [ -n "$task" ] && echo "$j|$task"
done
true
R
)
TASKF=$(mktemp)
RTXF=$(mktemp)
# Runs on the RTX VM: GPU summary, VM load/memory, and each GPU process with its owner and age.
# read -d '' (not $(cat <<...)): macOS bash 3.2 miscounts parentheses inside $( ).
IFS= read -r -d '' RTX_REMOTE <<'R'
echo "@@ME $(id -un)"
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit --format=csv,noheader,nounits | head -1 | sed 's/^/@@GPU /'
echo "@@SYS $(nproc) $(cut -d' ' -f1 /proc/loadavg) $(free -m | awk '/^Mem:/{print $3, $2}')"
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null | while IFS=', ' read -r pid mem; do
  [ "$pid" -gt 0 ] 2>/dev/null || continue
  set -- $(ps -o user:32=,etimes= -p "$pid" 2>/dev/null)
  cmd=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-90 | tr '|' '/')
  echo "@@P $pid|${1:-?}|${2:-0}|$mem|$cmd"
done
true
R

first=1
while true; do
  now=$(date "+%H:%M:%S")
  err=""
  if out=$("${SSH[@]}" bash -s -- "$PART" <<<"$REMOTE" 2>&1); then
    data=$(printf '%s\n' "$out" | sed '/^@@TASKS$/,$d')
    printf '%s\n' "$out" | sed '1,/^@@TASKS$/d' > "$TASKF"
  else
    err="$out"; data=""; : > "$TASKF"
  fi
  rtx_err=""
  if [ -n "$RTX_HOST" ]; then
    if ! "${SSHR[@]}" bash -s <<<"$RTX_REMOTE" > "$RTXF" 2> "$RTXF.err"; then
      rtx_err=$(head -c 300 "$RTXF.err" | tr '\n' ' '); [ -n "$rtx_err" ] || rtx_err="ssh $RTX_HOST failed"; : > "$RTXF"
    fi
  fi
  render "$data" "$now" "$err"
  if [ $first = 1 ]; then open "$OUT" 2>/dev/null || echo "open $OUT in your browser"; first=0; fi
  echo "$now updated $OUT"
  sleep "$INTERVAL"
done
