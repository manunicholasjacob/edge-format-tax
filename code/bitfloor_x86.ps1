# bitfloor_x86.ps1
# Cross-platform arm of the matched-byte test.
# H0 (Paper 12 law): decode tok/s = BW_eff / model_bytes, so implied BW = tok/s * bytes
#     must be a board constant, independent of quantization FORMAT.
# H1: formats with costlier weight unpacking show systematically lower implied BW at
#     matched byte counts, i.e. decode carries an unpack-compute term.
# The Pi 5 arm already falsified H0. This checks whether the same ordering appears on x86,
# where memory bandwidth is roughly 3x higher and the unpack term should matter MORE
# (more bandwidth per core means unpack work is a larger share of the critical path).

$ErrorActionPreference = "Continue"
$bin    = "C:\llmpc\bin"
$models = "C:\llmpc\models"
$work   = "C:\llmpc\bitfloor"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$src = Join-Path $models "qwen0.5b-q8.gguf"
$log = Join-Path $work "run.log"

function Log($m){ $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m; Write-Output $line; Add-Content -Path $log -Value $line -Encoding utf8 }

Log "start; source = $src"

# --- quantize the formats we do not already have -------------------------------
# Q4_0    : legacy 4-bit, scale + offset per block, cheapest unpack
# IQ4_NL  : 4-bit non-linear, lookup-table dequant, most expensive unpack
# IQ4_XS  : 4-bit non-linear in super-blocks
# Q4_K_M  : k-quant super-block (already present in models/)
# Q6_K    : 6-bit k-quant
# Q3_K_M  : 3-bit k-quant
$targets = @("Q4_0","IQ4_NL","IQ4_XS","Q6_K","Q3_K_M")
foreach($t in $targets){
  $out = Join-Path $work "qwen0.5b-$t.gguf"
  if(Test-Path $out){ Log "have $t"; continue }
  Log "quantize -> $t"
  & "$bin\llama-quantize.exe" --allow-requantize $src $out $t *>> (Join-Path $work "quantize.log")
  if(Test-Path $out){ Log ("  ok {0} bytes" -f (Get-Item $out).Length) } else { Log "  FAILED $t" }
}

# --- assemble the model list ---------------------------------------------------
$list = @()
foreach($t in $targets){
  $p = Join-Path $work "qwen0.5b-$t.gguf"
  if(Test-Path $p){ $list += $p }
}
foreach($n in @("qwen0.5b-q2k.gguf","qwen0.5b-q4km.gguf","qwen0.5b-q8.gguf")){
  $p = Join-Path $models $n
  if(Test-Path $p){ $list += $p }
}
Log ("benching {0} models" -f $list.Count)

# --- bench ---------------------------------------------------------------------
# -r 5 repetitions. Threads 2 / 4 / 6, all within the 6 P-cores of the i7-12700H
# so we never straddle the P/E boundary (Paper 14 showed those are different
# microarchitectures and mixing them would confound the format comparison).
$args = @()
foreach($m in $list){ $args += @("-m", $m) }
$args += @("-p","128","-n","128","-t","2,4,6","-r","5","-o","json")

$outJson = Join-Path $work "bench.json"
Log "llama-bench starting (this takes a while)"
& "$bin\llama-bench.exe" @args 2> (Join-Path $work "bench.err") | Out-File -FilePath $outJson -Encoding utf8
Log "llama-bench done -> $outJson"

# --- reduce --------------------------------------------------------------------
try{
  $rows = Get-Content $outJson -Raw | ConvertFrom-Json
  $summary = foreach($r in $rows){
    if($r.n_gen -gt 0){
      $bytes = (Get-Item $r.model_filename -ErrorAction SilentlyContinue).Length
      if(-not $bytes){ $bytes = $r.model_size }
      [PSCustomObject]@{
        model    = Split-Path $r.model_filename -Leaf
        threads  = $r.n_threads
        tok_s    = [math]::Round($r.avg_ts,3)
        bytes    = $bytes
        impliedBW_GBs = [math]::Round(($r.avg_ts * $bytes / 1e9),3)
      }
    }
  }
  $summary | Sort-Object threads, model | Format-Table -AutoSize | Out-String -Width 200 |
    Tee-Object -FilePath (Join-Path $work "summary.txt")
  $summary | ConvertTo-Json -Depth 3 | Out-File (Join-Path $work "summary.json") -Encoding utf8
}catch{
  Log ("reduce failed: {0}" -f $_.Exception.Message)
}
Log "DONE"
