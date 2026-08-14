# Your Quantization Format Is Not Free

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

1. **Provenance:** FP16-sourced files decode up to 38% faster than Q8-requantized
   files carrying the same format label and nominal bit width, because provenance
   silently changes per-tensor layouts. At sub-billion scale the output head alone is
   over 40% of the bytes streamed per token.
2. **The default is taxed where least expected:** normalized by bytes actually
   streamed, Q4_K_M (the community default) falls 16% (A76), 19% (Gracemont), and
   28% (Golden Cove) below the streaming envelope at 0.5B, costing 44% more energy per
   token on the Pi than an i-quant of near-identical quality.
3. **Rankings do not transfer:** the fastest 4-bit format on P-cores (Q4_0) is
   mid-pack on E-cores, where IQ4_NL wins by 19%; on the A76 the 4-bit class converges.

The pattern fits a two-term cost model, decode time as the maximum of a streaming term
and a per-(format, kernel, core) compute term, and tracks the uneven coverage of
architecture-specific repacked kernels in today's runtimes.

## Layout

```
code/    quantization + benchmark drivers (Pi bash, x86 PowerShell), figure scripts
data/    raw measurement records, per-format quantization logs, repack-coverage logs,
         PMIC energy, perplexity, and the reverse-order / HT-placement control runs
paper/   the compiled HotMobile 2027 manuscript
```

Key data files:
- `data/pi5_canonical.jsonl` — canonical FP16-sourced artifacts on the A76 (llama-bench + 10 Hz PMIC)
- `data/pi5_perf_repack.jsonl` — perf-counter kernel attribution (instructions/token, IPC)
- `data/x86_bench.json`, `data/bench_ecore.json` — Golden Cove and Gracemont sweeps
- `data/repack/`, `data/repack15/` — runtime repack-kernel coverage logs, both scales
- `data/pi5_canonical_quant.log` — per-tensor quantization log (the 256-divisibility fallback)

## Reproducing

Pi arm: `code/bitfloor_pi.sh` (native llama.cpp build with dot-product extensions, PMIC
sampled at 10 Hz in a separate identical run). x86 arms: `code/bitfloor_x86.ps1` and
`code/bitfloor_ecore.ps1` (affinity-masked to P-cores or E-cores). Figures:
`code/gen_fig1.py`. See `ABOUT.md` for the full description and venue.

## Citation

See `CITATION.cff`. This artifact is archived on Zenodo; the DOI badge will appear here
once the first release is minted.

## License

MIT (see `LICENSE`). Measurement data is released for reuse with attribution.
