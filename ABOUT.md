# Your Quantization Format Is Not Free

Public artifact for the HotMobile 2027 submission "Your Quantization Format Is Not Free:
Same-Size, Same-Label GGUF Files Decode Very Differently on Edge CPUs". Measurements on
three CPU microarchitectures: Cortex-A76 (Raspberry Pi 5, with PMIC energy), Gracemont
E-cores and Golden Cove P-cores (i7-12700H, pinned separately), on artifacts quantized
from the official FP16 GGUF.

Findings:

1. The label is not the bit rate: at sub-billion scale `llama-quantize` substitutes other
   types per tensor, so a file's real bits per weight differ from what its label suggests.
2. The community-default Q4_K_M sits below the streaming envelope on every core at 0.5B
   and recovers at 1.5B.
3. What transfers is the tax, not the ranking: in randomized order the competitive 4-bit
   formats finish close together across the core types of one SoC.

Methodological contribution: normalize throughput by streamed bytes (repeating layers plus
output head), not file bytes.

## Venue

HotMobile 2027 (Tucson AZ, 24-25 Feb 2027). Notification 16 Dec 2026. The manuscript will
be linked here once it is public.

## Files

- `data/` - measurement records, quantization and repack-coverage logs, PMIC energy,
  perplexity, control runs
- `code/` - benchmark drivers and figure scripts
