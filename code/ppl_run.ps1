# ppl_run.ps1 - perplexity per format on the FP16-SOURCED artifacts (quality-valid).
# Corpus: Project Gutenberg War and Peace (Paper 12 precedent; wikitext URL is dead).
# 100 chunks x 512 ctx = ~51K tokens; P-cores; run ONLY after the E-core bench finishes.
$ErrorActionPreference = "Continue"
$bin  = "C:\llmpc\bin\llama-perplexity.exe"
$q    = "C:\llmpc\fp16quant"
$fp16 = "C:\llmpc\models\qwen0.5b-fp16.gguf"
$corp = "C:\llmpc\corpus_wap.txt"
$out  = "C:\llmpc\bitfloor\ppl_results.txt"
"model,ppl,err" | Out-File $out -Encoding utf8

$models = @{
  "FP16"    = $fp16
  "Q8_0"    = (Join-Path $q "qwen0.5b-Q8_0.fp16src.gguf")
  "Q4_0"    = (Join-Path $q "qwen0.5b-Q4_0.fp16src.gguf")
  "Q3_K_M"  = (Join-Path $q "qwen0.5b-Q3_K_M.fp16src.gguf")
  "IQ4_NL"  = (Join-Path $q "qwen0.5b-IQ4_NL.fp16src.gguf")
  "IQ4_XS"  = (Join-Path $q "qwen0.5b-IQ4_XS.fp16src.gguf")
  "Q4_K_M"  = (Join-Path $q "qwen0.5b-Q4_K_M.fp16src.gguf")
  "Q2_K"    = (Join-Path $q "qwen0.5b-Q2_K.fp16src.gguf")
  "Q6_K"    = (Join-Path $q "qwen0.5b-Q6_K.fp16src.gguf")
}
foreach($k in @("FP16","Q8_0","Q6_K","Q4_K_M","Q4_0","IQ4_NL","IQ4_XS","Q3_K_M","Q2_K")){
  $m = $models[$k]
  if(-not (Test-Path $m)){ "$k,MISSING," | Add-Content $out; continue }
  Write-Output ("[{0}] ppl {1}" -f (Get-Date -Format HH:mm:ss), $k)
  $txt = & $bin -m $m -f $corp --chunks 100 -t 6 2>&1 | Out-String
  if($txt -match "Final estimate: PPL = ([0-9.]+) \+/- ([0-9.]+)"){
    "$k,$($Matches[1]),$($Matches[2])" | Add-Content $out
  } else {
    "$k,PARSE_FAIL," | Add-Content $out
    $txt | Out-File (Join-Path (Split-Path $out) "ppl_raw_$k.txt") -Encoding utf8
  }
}
Get-Content $out
