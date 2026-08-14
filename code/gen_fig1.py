"""Fig. 1: implied bandwidth (tok/s x model bytes) per format on both platforms.
If decode were purely byte-streaming, every bar within a platform would be equal."""
import matplotlib
matplotlib.rcParams["pdf.fonttype"] = 42  # DATE lesson: never embed Type-3
matplotlib.rcParams["ps.fonttype"] = 42
import matplotlib.pyplot as plt
import numpy as np, pathlib

out = pathlib.Path(__file__).resolve().parent.parent / "paper" / "fig1_impliedbw.pdf"

# measured, 9 Aug 2026, llama-bench -p 128 -n 128, decode (tg) rows, best-thread=2 on Pi
formats = ["Q4_0", "Q8_0", "Q2_K", "Q3_K_M", "Q4_K_M", "Q5_K_M", "Q6_K", "IQ4_NL", "IQ4_XS"]
pi_bw   = [11.33, 11.52, 10.56, 11.12, 9.87, 9.50, 9.66, 9.20, 8.69]     # GB/s, t=2
x86_bw  = [19.57, 20.62, 18.70, 20.11, 16.52, None, 20.21, 19.34, 19.03] # GB/s, t=2 (no Q5_K_M run)

fam = {"Q4_0":"legacy", "Q8_0":"legacy", "Q2_K":"k-quant", "Q3_K_M":"k-quant",
       "Q4_K_M":"k-quant", "Q5_K_M":"k-quant", "Q6_K":"k-quant",
       "IQ4_NL":"i-quant (LUT)", "IQ4_XS":"i-quant (LUT)"}
colors = {"legacy":"#31708f", "k-quant":"#7f9c5a", "i-quant (LUT)":"#b5563c"}

fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.5), sharey=False)
for ax, vals, title, ylim in (
        (axes[0], pi_bw,  "Raspberry Pi 5 (Cortex-A76), 2 threads", (0, 13)),
        (axes[1], x86_bw, "i7-12700H (P-cores), 2 threads", (0, 23))):
    xs, ys, cs, labs = [], [], [], []
    for i, (f, v) in enumerate(zip(formats, vals)):
        if v is None:
            continue
        xs.append(len(xs)); ys.append(v); cs.append(colors[fam[f]]); labs.append(f)
    ax.bar(xs, ys, color=cs, width=0.72)
    ax.set_xticks(xs)
    ax.set_xticklabels(labs, rotation=45, ha="right", fontsize=7)
    ax.set_title(title, fontsize=8)
    ax.set_ylim(*ylim)
    ax.tick_params(labelsize=7)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    ax.set_axisbelow(True)
axes[0].set_ylabel("implied bandwidth\n(tok/s $\\times$ bytes, GB/s)", fontsize=8)

handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in colors.values()]
fig.legend(handles, list(colors.keys()), loc="upper center", ncol=3, fontsize=7,
           frameon=False, bbox_to_anchor=(0.5, 1.13))
fig.tight_layout()
fig.savefig(out, bbox_inches="tight")
print("wrote", out)
