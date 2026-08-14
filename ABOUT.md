# Paper 16 -- Your Quantization Format Is Not Free

Same-size, same-label GGUF files decode very differently on edge CPUs. Three
measured findings on three microarchitectures (Cortex-A76 / Pi 5 with PMIC
energy, Gracemont E-cores, Golden Cove P-cores, canonical FP16-sourced
artifacts):

1. Same-label files differ up to 38% in decode speed by quantization provenance
2. The community-default Q4_K_M sits 16-28% below the streaming envelope on
   every core and costs +44% energy/token on the Pi vs IQ4_XS at a 0.58-ppl
   difference
3. Format rankings do not transfer across cores (Q4_0 wins P-cores, IQ4_NL wins
   E-cores, A76 converges), consistent with per-ISA repack-kernel coverage

Methodological contribution: normalize by STREAMED bytes (repeating layers +
output head), not file bytes; at 0.5B the head is 42% of streamed traffic.

## Venue

**HotMobile 2027** (Tucson AZ, 24-25 Feb 2027). Deadline **9 Oct 2026 AoE**,
notification 16 Dec 2026. 6 pp incl refs, non-anonymous, ACM DL archival.
Full venue analysis in `PAPERS_STATUS.md`.

Earlier draft targeted ODI @ NeurIPS 2026 (in `paper/`); the HotMobile
retarget is in `paper-hotmobile/` and is the current submission target.

## Files

- `paper-hotmobile/` -- current HotMobile draft (v3.2, acmart sigconf)
- `paper/` -- earlier NeurIPS ODI draft (superseded)
- `data/` -- pi5_results.jsonl, x86_bench.json, canonical quant logs, repack logs
- `code/` -- bitfloor_pi.sh, bitfloor_x86.ps1, gen_fig1.py
- `PRE_SUBMISSION_AUDIT.md` -- 3-reviewer audit with 5 critical fixes (all applied in v3.2)
