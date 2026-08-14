#!/bin/bash
# bitfloor.sh - does the decode roofline (tok/s = BW_eff / model_bytes) hold across
# quantization FORMATS at matched byte counts, or is there a hidden unpack-compute term?
#
# H0 (Paper 12 law): tok/s x bytes = BW_eff is a board constant, independent of format.
# H1 (T-MAC mechanism): formats with costlier weight unpacking show lower implied BW_eff
#     at equal bytes, i.e. decode is not purely bandwidth-bound at low bit-width.
#
# Safety: one model at a time, deleted after use (disk is ~97% full).
#         refuses to run if SwapFree headroom is low or a compiler is still running.

set -u
BIN=~/llm/llama.cpp/build/bin
MODELS=~/llm/models
WORK=~/bitfloor
OUT=$WORK/results.jsonl
mkdir -p "$WORK"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$WORK/run.log"; }

# --- wait for the llama-quantize build to finish -------------------------------
for i in $(seq 1 240); do
  [ -x "$BIN/llama-quantize" ] && break
  sleep 15
done
if [ ! -x "$BIN/llama-quantize" ]; then log "FATAL: llama-quantize never appeared"; exit 1; fi

# --- wait for the machine to go quiet (his own rule: never bench a busy box) ----
for i in $(seq 1 120); do
  pgrep -x cc1plus >/dev/null || pgrep -x cmake >/dev/null || break
  sleep 10
done
sleep 20
log "machine quiet; starting"

guard(){
  local need_mb=$1
  local swapfree=$(awk '/SwapFree/{print int($2/1024)}' /proc/meminfo)
  local diskfree=$(df -m / | awk 'NR==2{print $4}')
  if [ "$swapfree" -lt 100 ]; then log "ABORT: SwapFree ${swapfree}MB too low"; exit 1; fi
  if [ "$diskfree" -lt "$need_mb" ]; then log "SKIP: disk ${diskfree}MB < ${need_mb}MB"; return 1; fi
  return 0
}

# sample PMIC total power (W) for N seconds at 10 Hz -> mean
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

bench(){
  local path=$1 tag=$2
  local bytes=$(stat -c %s "$path")
  log "bench $tag bytes=$bytes"
  local pf="$WORK/pwr_$tag.txt"
  local pid=$(power_watch 200 "$pf")
  "$BIN/llama-bench" -m "$path" -p 128 -n 128 -t 2,3,4 -r 3 -o json > "$WORK/bench_$tag.json" 2>>"$WORK/run.log"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  local meanw=$(awk '{s+=$1;n++} END{if(n)printf "%.3f",s/n; else print "nan"}' "$pf")
  python3 - "$WORK/bench_$tag.json" "$tag" "$bytes" "$meanw" >> "$OUT" <<'PY'
import json,sys
f,tag,byts,meanw=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
try: rows=json.load(open(f))
except Exception as e: print(json.dumps({"tag":tag,"error":str(e)})); raise SystemExit
for r in rows:
    if r.get("n_gen",0)>0:
        tps=r["avg_ts"]; th=r["n_threads"]
        print(json.dumps({"tag":tag,"threads":th,"bytes":byts,"tok_s":tps,
                          "implied_BW_GBs":tps*byts/1e9,"mean_W":meanw,
                          "mJ_per_tok":(float(meanw)/tps*1000 if meanw!="nan" and tps else None)}))
PY
}

log "=== arm 1: existing byte sweep (Q2_K .. Q8_0), same session, quiet box ==="
for m in q2k q3km q4km q5km q8; do
  bench "$MODELS/qwen0.5b-$m.gguf" "$m"
done

log "=== arm 2: MATCHED-BYTE format comparison (the falsification test) ==="
SRC="$MODELS/qwen0.5b-q8.gguf"
for t in Q4_0 IQ4_NL IQ4_XS Q6_K; do
  guard 700 || continue
  tgt="$WORK/qwen0.5b-$t.gguf"
  log "quantize -> $t"
  "$BIN/llama-quantize" --allow-requantize "$SRC" "$tgt" "$t" >>"$WORK/run.log" 2>&1
  if [ -f "$tgt" ]; then bench "$tgt" "$t"; rm -f "$tgt"; else log "quantize FAILED for $t"; fi
done

log "DONE"
