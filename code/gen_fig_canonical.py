"""Fig. 1 (canonical): decode throughput normalized by STREAMED bytes per token,
per format per core type. If the byte-streaming law held per platform, all bars
within a panel would be equal."""
import matplotlib
matplotlib.rcParams["pdf.fonttype"] = 42
matplotlib.rcParams["ps.fonttype"] = 42
import matplotlib.pyplot as plt
import pathlib

out = pathlib.Path(__file__).resolve().parent.parent / "paper-hotmobile" / "fig1_streamed.pdf"

# streamed MiB per token-step (repeating + output head; embedding row negligible)
streamed = {"Q4_0":330.2, "IQ4_NL":332.2, "IQ4_XS":329.5, "Q3_K_M":333.6,
            "Q2_K":317.4, "Q4_K_M":374.2, "Q6_K":476.8, "Q8_0":501.0}
MB = 1.048576  # MiB -> MB

# canonical-artifact tok/s (llama-bench tg128, r=5)
a76_t2 = {"Q4_0":34.66,"IQ4_XS":34.23,"IQ4_NL":34.23,"Q3_K_M":33.35,
          "Q2_K":31.80,"Q4_K_M":25.68,"Q6_K":23.39,"Q8_0":22.22}
gc_t2  = {"Q4_0":66.49,"IQ4_NL":55.97,"IQ4_XS":53.34,"Q3_K_M":54.38,
          "Q2_K":54.62,"Q4_K_M":42.40,"Q6_K":44.00,"Q8_0":42.63}
gc_t6  = {"Q4_0":111.42,"IQ4_NL":105.52,"IQ4_XS":101.04,"Q3_K_M":100.27,
          "Q2_K":103.72,"Q4_K_M":89.94,"Q6_K":78.74,"Q8_0":81.37}
em_t2  = {"Q4_0":18.78,"IQ4_NL":19.35,"IQ4_XS":18.09,"Q3_K_M":19.70,
          "Q2_K":18.15,"Q4_K_M":13.37,"Q6_K":17.86,"Q8_0":16.75}
em_t4  = {"Q4_0":35.07,"IQ4_NL":43.56,"IQ4_XS":36.73,"Q3_K_M":36.44,
          "Q2_K":36.20,"Q4_K_M":29.33,"Q6_K":28.53,"Q8_0":31.19}

order = ["Q4_0","IQ4_NL","IQ4_XS","Q3_K_M","Q2_K","Q4_K_M","Q6_K","Q8_0"]
def bw(d): return [d[f]*streamed[f]*MB/1e3 for f in order]  # GB/s

panels = [
    ("Cortex-A76 (Pi 5), 2T", [("2 threads", bw(a76_t2), "#31708f")]),
    ("Gracemont E-cores", [("2 threads", bw(em_t2), "#9fbcd0"), ("4 threads", bw(em_t4), "#31708f")]),
    ("Golden Cove P-cores", [("2 threads", bw(gc_t2), "#9fbcd0"), ("6 threads", bw(gc_t6), "#31708f")]),
]

fig, axes = plt.subplots(1, 3, figsize=(7.0, 2.3))
for ax, (title, series) in zip(axes, panels):
    n = len(series)
    w = 0.72/n
    for i, (lab, vals, col) in enumerate(series):
        xs = [x + (i - (n-1)/2)*w for x in range(len(order))]
        ax.bar(xs, vals, width=w, color=col, label=lab)
    ax.set_xticks(range(len(order)))
    ax.set_xticklabels(order, rotation=55, ha="right", fontsize=6.3)
    ax.set_title(title, fontsize=7.5)
    ax.tick_params(labelsize=6.5)
    ax.grid(axis="y", alpha=0.25, linewidth=0.5)
    ax.set_axisbelow(True)
    if n > 1:
        ax.legend(fontsize=6, frameon=False, loc="upper left", handlelength=1.0)
axes[0].set_ylabel("streamed-byte throughput\n(GB/s)", fontsize=7.5)
fig.tight_layout()
fig.savefig(out, bbox_inches="tight")
print("wrote", out)
