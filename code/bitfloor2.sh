#!/bin/bash
# bitfloor2.sh - clean rerun addressing both validity caveats of the first pass:
#   pass A per model: llama-bench UNPERTURBED (no power sampler), t=2,3,4, r=5
#   pass B per model: identical load with the 10 Hz PMIC sampler running, power only
# Requants are produced one at a time and deleted (disk headroom ~2.3 GB).
set -u
BIN=~/llm/llama.cpp/build/bin
MODELS=~/llm/models
WORK=~/bitfloor2
OUT=$WORK/results2.jsonl
mkdir -p "$WORK"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$WORK/run.log"; }

guard(){
  local swapfree=$(awk '/SwapFree/{print int($2/1024)}' /proc/meminfo)
  if [ "$swapfree" -lt 100 ]; then log "ABORT: SwapFree ${swapfree}MB"; exit 1; fi
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

bench_clean(){
  local path=$1 tag=$2
  local bytes=$(stat -c %s "$path")
  guard
  log "PASS A (unperturbed) $tag"
  "$BIN/llama-bench" -m "$path" -p 128 -n 128 -t 2,3,4 -r 5 -o json > "$WORK/benchA_$tag.json" 2>>"$WORK/run.log"
  log "PASS B (power) $tag"
  local pf="$WORK/pwr_$tag.txt"
  local pid=$(power_watch 180 "$pf")
  "$BIN/llama-bench" -m "$path" -p 128 -n 128 -t 2 -r 3 -o json > /dev/null 2>>"$WORK/run.log"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  local meanw=$(awk '{s+=$1;n++} END{if(n)printf "%.3f",s/n; else print "nan"}' "$pf")
  python3 - "$WORK/benchA_$tag.json" "$tag" "$bytes" "$meanw" >> "$OUT" <<'PY'
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
  log "done $tag"
}

log "=== native ladder ==="
for m in q2k q3km q4km q5km q8; do bench_clean "$MODELS/qwen0.5b-$m.gguf" "$m"; done

log "=== requant arm (one at a time) ==="
SRC="$MODELS/qwen0.5b-q8.gguf"
for t in Q4_0 IQ4_NL IQ4_XS Q6_K; do
  free_mb=$(df -m / | awk 'NR==2{print $4}')
  if [ "$free_mb" -lt 700 ]; then log "SKIP $t disk ${free_mb}MB"; continue; fi
  tgt="$WORK/qwen0.5b-$t.gguf"
  "$BIN/llama-quantize" --allow-requantize "$SRC" "$tgt" "$t" >>"$WORK/run.log" 2>&1
  if [ -f "$tgt" ]; then bench_clean "$tgt" "$t"; rm -f "$tgt"; else log "quantize FAILED $t"; fi
done
log "DONE"
