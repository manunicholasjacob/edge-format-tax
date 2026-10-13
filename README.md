# Your Quantization Format Is Not Free

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21938812.svg)](https://doi.org/10.5281/zenodo.21938812)

**Same-size, same-label GGUF files decode very differently on edge CPUs.**

Public artifact for the HotMobile 2027 submission. All measurements are on the
author's own hardware: a Raspberry Pi 5 (Cortex-A76, on-board PMIC energy) and an
Intel i7-12700H (Gracemont E-cores and Golden Cove P-cores pinned separately).

## The findings

On-device LLM deployment is guided by a byte-streaming mental model: decode reads
every weight per token, so throughput and energy are set by model bytes, and a
quantization format is chosen by accuracy per byte. Controlled measurements on three
CPU microarchitectures show the format *label* is a poor predictor of what a GGUF
file actually costs.

1. **The label is not the bit rate.** At sub-billion scale the embedding dimension does not
   divide into the 256-element blocks the K-quants and i-quants need, so `llama-quantize`
   substitutes other types per tensor and ships a file whose real bits per weight differ
   from what its label suggests.
2. **The community default is taxed.** Normalized by the bytes actually streamed per token,
   Q4_K_M sits below the streaming envelope on all three cores at 0.5B and recovers at 1.5B.
3. **What transfers is the tax, not the ranking.** Measured in randomized order, the
   competitive 4-bit formats finish close together across the P-cores and E-cores of one
   SoC; across ISAs, where kernel coverage differs, the ranking does move.

The full numbers are in the paper and will be added here after the review concludes.

The pattern fits a two-term cost model, decode time as the maximum of a streaming term
and a per-(format, kernel, core) compute term, and tracks the uneven coverage of
architecture-specific repacked kernels in today's runtimes.

## Layout

```
code/    quantization + benchmark drivers (Pi bash, x86 PowerShell), figure scripts
data/    raw measurement records, per-format quantization logs, repack-coverage logs,
         PMIC energy, perplexity, and the reverse-order / HT-placement / random-order
         control runs
```

Key data files:
- `data/pi5_canonical.jsonl` - canonical FP16-sourced artifacts on the A76 (llama-bench + 10 Hz PMIC)
- `data/pi5_perf_repack.jsonl` - perf-counter kernel attribution (instructions/token, IPC)
- `data/x86_bench.json`, `data/bench_ecore.json` - Golden Cove and Gracemont sweeps
- `data/repack/`, `data/repack15/` - runtime repack-kernel coverage logs, both scales
- `data/pi5_canonical_quant.log` - per-tensor quantization log (the 256-divisibility fallback)
- `data/x86_iquant_order_t2.jsonl`, `data/x86_iquant_order_t4t6.jsonl` - x86 4-bit formats in
  four seeded random-order passes (Golden Cove at 2 and 6 threads, Gracemont at 2 and 4)

## Reproducing

Pi arm: `code/bitfloor_pi.sh` (native llama.cpp build with dot-product extensions, PMIC
sampled at 10 Hz in a separate identical run). x86 arms: `code/bitfloor_x86.ps1` and
`code/bitfloor_ecore.ps1` (affinity-masked to P-cores or E-cores). Figures:
`code/gen_fig1.py`. See `ABOUT.md` for the venue.

## Citation

See `CITATION.cff`. Archived on Zenodo; the concept DOI
[10.5281/zenodo.21938812](https://doi.org/10.5281/zenodo.21938812) always resolves to the latest version.

## License

MIT (see `LICENSE`). Measurement data is released for reuse with attribution.
