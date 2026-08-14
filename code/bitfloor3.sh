#!/bin/bash
# bitfloor3.sh - canonical-artifact arm on the Pi: quantize each format FROM THE FP16
# SOURCE on-device (source scp'd to ~/bitfloor3/fp16.gguf beforehand), bench clean
# (pass A unperturbed, pass B power-only), delete, next. Waits for bitfloor2 to finish.
set -u
BIN=~/llm/llama.cpp/build/bin
WORK=~/bitfloor3
SRC=$WORK/fp16.gguf
OUT=$WORK/results3.jsonl
mkdir -p "$WORK"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$WORK/run.log"; }

# wait for bitfloor2 to complete (max ~90 min)
for i in $(seq 1 270); do
  grep -q "^\[.*\] DONE" ~/bitfloor2/run.log 2>/dev/null && break
  sleep 20
done
sleep 15
log "bitfloor2 finished; starting canonical arm"

[ -f "$SRC" ] || { log "FATAL: fp16 source missing"; exit 1; }

guard(){
  local avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  local disk=$(df -m / | awk 'NR==2{print $4}')
  if [ "$avail" -lt 800 ]; then log "ABORT: MemAvailable ${avail}MB"; exit 1; fi
  if [ "$disk" -lt 750 ]; then log "SKIP-DISK ${disk}MB"; return 1; fi
  return 0
}

power_watch(){
  local secs=$1 out=$2
  ( end=$((SECONDS+secs))
    while [ $SECONDS -lt $end ]; do
      vcgencmd pmic_read_adc 2>/dev/null | awk '
        /current\(/{split($0,a,"="); c[$1]=a[2]+0}
        /volt\(/{split($0,a,"="); v[$1]=a[2]+0}
        END{p=0; for(k in c){ n=k; sub(/_A$/,"",n); vk=n"_V"; if(vk in v) p+=c[k]*v[vk]} print p}'
      sleep 0.1
    done ) > "$out" 2>/dev/null &
  echo $!
}

for t in Q4_0 IQ4_NL IQ4_XS Q3_K_M Q4_K_M Q2_K Q6_K Q8_0; do
  guard || continue
  tgt="$WORK/m-$t.gguf"
  log "quantize fp16 -> $t"
  "$BIN/llama-quantize" "$SRC" "$tgt" "$t" >>"$WORK/quant.log" 2>&1
  [ -f "$tgt" ] || { log "quantize FAILED $t"; continue; }
  bytes=$(stat -c %s "$tgt")
  log "PASS A $t bytes=$bytes"
  "$BIN/llama-bench" -m "$tgt" -p 128 -n 128 -t 2,3,4 -r 5 -o json > "$WORK/benchA_$t.json" 2>>"$WORK/run.log"
  log "PASS B $t"
  pf="$WORK/pwr_$t.txt"
  pid=$(power_watch 180 "$pf")
  "$BIN/llama-bench" -m "$tgt" -p 128 -n 128 -t 2 -r 3 -o json > /dev/null 2>>"$WORK/run.log"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  meanw=$(awk '{s+=$1;n++} END{if(n)printf "%.3f",s/n; else print "nan"}' "$pf")
  python3 - "$WORK/benchA_$t.json" "$t" "$bytes" "$meanw" >> "$OUT" <<'PY'
import json,sys
f,tag,byts,meanw=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
try: rows=json.load(open(f))
except Exception as e: print(json.dumps({"tag":tag,"error":str(e)})); raise SystemExit
for r in rows:
    if r.get("n_gen",0)>0:
        print(json.dumps({"tag":tag,"threads":r["n_threads"],"bytes":byts,
            "tok_s":r["avg_ts"],"stddev":r.get("stddev_ts"),
            "implied_BW_GBs":r["avg_ts"]*byts/1e9,"mean_W_separate_run":meanw,
            "mJ_per_tok":(float(meanw)/r["avg_ts"]*1000 if meanw!="nan" and r["avg_ts"] else None)}))
PY
  rm -f "$tgt"
  log "done $t"
done
log "DONE"
