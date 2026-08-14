# bitfloor_ecore.ps1
# Third platform arm: Gracemont E-cores (CPUs 12-19, mask 0xFF000) on the i7-12700H.
# Paper 14 established P/E pinning on this machine (P=0-11 at 94-100% scalar peak, E=12-19 at 41-44%).
# The E-cores sit BETWEEN Cortex-A76 and Golden Cove in compute-per-byte, so they locate the
# crossover the two-term model predicts. Same DRAM as the P-core arm = compute isolated cleanly.

$ErrorActionPreference = "Continue"
$bin  = "C:\llmpc\bin"
$work = "C:\llmpc\bitfloor"
$models = "C:\llmpc\models"
$log = Join-Path $work "ecore.log"
function Log($m){ $line="[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m; Write-Output $line; Add-Content $log $line -Encoding utf8 }

$list = @(
  (Join-Path $work "qwen0.5b-Q4_0.gguf"),
  (Join-Path $work "qwen0.5b-IQ4_NL.gguf"),
  (Join-Path $work "qwen0.5b-IQ4_XS.gguf"),
  (Join-Path $work "qwen0.5b-Q3_K_M.gguf"),
  (Join-Path $work "qwen0.5b-Q6_K.gguf"),
  (Join-Path $models "qwen0.5b-q2k.gguf"),
  (Join-Path $models "qwen0.5b-q4km.gguf"),
  (Join-Path $models "qwen0.5b-q8.gguf")
) | Where-Object { Test-Path $_ }
Log ("E-core arm: {0} models" -f $list.Count)

$args = @()
foreach($m in $list){ $args += @("-m", ('"'+$m+'"')) }
$args += @("-p","128","-n","128","-t","2,4,8","-r","5","-o","json")
$argStr = $args -join " "
$outJson = Join-Path $work "bench_ecore.json"

# start /affinity applies the mask at process creation, so llama-bench threads inherit it.
# FF000 = logical CPUs 12-19 (the 8 Gracemont E-cores, no HT).
$cmdLine = 'start "" /affinity FF000 /B /WAIT "' + $bin + '\llama-bench.exe" ' + $argStr + ' > "' + $outJson + '" 2>"' + (Join-Path $work "ecore.err") + '"'
Log "launching pinned to E-cores (mask FF000)"
cmd /c $cmdLine
Log "bench done"

try{
  $rows = Get-Content $outJson -Raw | ConvertFrom-Json
  $summary = foreach($r in $rows){
    if($r.n_gen -gt 0){
      $bytes = (Get-Item $r.model_filename -ErrorAction SilentlyContinue).Length
      if(-not $bytes){ $bytes = $r.model_size }
      [PSCustomObject]@{ model=Split-Path $r.model_filename -Leaf; threads=$r.n_threads
        tok_s=[math]::Round($r.avg_ts,3); bytes=$bytes
        impliedBW_GBs=[math]::Round(($r.avg_ts*$bytes/1e9),3) }
    }
  }
  $summary | Sort-Object threads, model | Format-Table -AutoSize | Out-String -Width 200 |
    Tee-Object -FilePath (Join-Path $work "summary_ecore.txt")
  $summary | ConvertTo-Json -Depth 3 | Out-File (Join-Path $work "summary_ecore.json") -Encoding utf8
}catch{ Log ("reduce failed: {0}" -f $_.Exception.Message) }
Log "DONE"
