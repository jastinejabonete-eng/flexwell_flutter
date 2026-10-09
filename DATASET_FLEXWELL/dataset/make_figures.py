# -*- coding: utf-8 -*-
"""
Generate presentation-quality visualizations for the algorithm comparison.
Reads algo_comparison.csv, writes PNGs ready to insert into the paper.

Outputs (in dataset/figures/):
  fig_algo_accuracy_by_exercise.png   grouped bars: CV accuracy per exercise x algorithm
  fig_algo_accuracy_overall.png       horizontal bars: mean accuracy across exercises
  fig_algo_metrics_heatmap.png        heatmap: precision/recall/F1 per algorithm
  fig_algo_knn_vs_rest.png            KNN vs best-other gap per exercise
"""
import os
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

OUT_DIR = "figures"
os.makedirs(OUT_DIR, exist_ok=True)

df = pd.read_csv("algo_comparison.csv")

# Paper-friendly styling: readable at ~6 inches wide, 200 dpi.
plt.rcParams.update({
    "figure.dpi": 200,
    "savefig.dpi": 200,
    "font.size": 9,
    "axes.titlesize": 11,
    "axes.titleweight": "bold",
    "axes.labelsize": 9,
    "axes.edgecolor": "#444444",
    "axes.grid": True,
    "grid.alpha": 0.25,
    "grid.linestyle": "--",
    "figure.facecolor": "white",
    "axes.facecolor": "white",
    "savefig.facecolor": "white",
})

PALETTE = ["#0D47A1", "#CCFF00", "#2ECC71", "#E53935", "#7E57C2", "#FF9800", "#00838F"]
COLORS = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(sorted(df.algorithm.unique()))}

EX_ORDER = ["Push-Up", "Plank", "Side Plank", "Lunge", "Pull-Up"]
EX_ORDER = [e for e in EX_ORDER if e in set(df.exercise)]

# ---------------------------------------------------------------- Figure 1
piv = df.pivot_table(index="exercise", columns="algorithm",
                     values="cv_accuracy", aggfunc="mean").reindex(EX_ORDER)
algos = sorted(df.algorithm.unique())

fig, ax = plt.subplots(figsize=(7.2, 3.9))
x = np.arange(len(piv.index))
w = 0.11
for i, a in enumerate(algos):
    if a in piv.columns:
        ax.bar(x + (i - len(algos) / 2) * w + w / 2, piv[a], w,
               label=a, color=COLORS[a], edgecolor="#333", linewidth=0.4)
ax.set_xticks(x)
ax.set_xticklabels(piv.index)
ax.set_ylabel("Grouped-CV Accuracy")
ax.set_ylim(0, 1.0)
ax.set_title("Classification Accuracy by Exercise and Algorithm")
ax.legend(ncol=2, fontsize=7.5, loc="upper right", framealpha=0.9)
ax.set_axisbelow(True)
fig.tight_layout()
fig.savefig(f"{OUT_DIR}/fig_algo_accuracy_by_exercise.png")
plt.close(fig)

# ---------------------------------------------------------------- Figure 2
mean_cv = df.groupby("algorithm").cv_accuracy.mean().sort_values()
fig, ax = plt.subplots(figsize=(6.6, 3.6))
bars = ax.barh(mean_cv.index, mean_cv.values,
               color=[COLORS[a] for a in mean_cv.index],
               edgecolor="#333", linewidth=0.5)
for b, v in zip(bars, mean_cv.values):
    ax.text(v + 0.006, b.get_y() + b.get_height() / 2, f"{v:.3f}",
            va="center", fontsize=8.5)
ax.set_xlim(0, 1.0)
ax.set_xlabel("Mean Grouped-CV Accuracy (across 5 exercises)")
ax.set_title("Overall Algorithm Comparison (Squat excluded)")
ax.set_axisbelow(True)
fig.tight_layout()
fig.savefig(f"{OUT_DIR}/fig_algo_accuracy_overall.png")
plt.close(fig)

# ---------------------------------------------------------------- Figure 3
metrics = df.groupby("algorithm")[["precision", "recall", "f1"]].mean().reindex(mean_cv.index)
fig, ax = plt.subplots(figsize=(6.8, 3.6))
data = metrics.values
im = ax.imshow(data, cmap="YlGnBu", vmin=0.4, vmax=1.0, aspect="auto")
ax.set_xticks(range(len(metrics.columns)))
ax.set_xticklabels(["Precision", "Recall", "F1-Score"])
ax.set_yticks(range(len(metrics.index)))
ax.set_yticklabels(metrics.index)
for i in range(data.shape[0]):
    for j in range(data.shape[1]):
        ax.text(j, i, f"{data[i, j]:.2f}", ha="center", va="center",
                fontsize=8.5, color="white" if data[i, j] > 0.72 else "black")
ax.set_title("Mean Precision / Recall / F1 by Algorithm")
ax.grid(False)
fig.colorbar(im, ax=ax, shrink=0.85, label="Score")
fig.tight_layout()
fig.savefig(f"{OUT_DIR}/fig_algo_metrics_heatmap.png")
plt.close(fig)

# ---------------------------------------------------------------- Figure 4
knn = piv["KNN (k=5)"] if "KNN (k=5)" in piv.columns else None
if knn is not None:
    others = [a for a in algos if a != "KNN (k=5)"]
    best_other = piv[others].max(axis=1) if others else None
    fig, ax = plt.subplots(figsize=(6.8, 3.6))
    xx = np.arange(len(piv.index))
    if best_other is not None:
        ax.bar(xx - 0.19, best_other.values, 0.36,
               label="Best other algorithm", color="#90A4AE",
               edgecolor="#333", linewidth=0.5)
        ax.bar(xx + 0.19, knn.values, 0.36,
               label="KNN (k=5)", color="#CCFF00",
               edgecolor="#333", linewidth=0.5)
        for i, (a, b) in enumerate(zip(best_other.values, knn.values)):
            ax.text(i, max(a, b) + 0.02, f"{b - a:+.2f}", ha="center",
                    fontsize=8, fontweight="bold")
        ax.set_xticks(xx)
        ax.set_xticklabels(piv.index)
        ax.set_ylim(0, 1.0)
        ax.set_ylabel("Grouped-CV Accuracy")
        ax.set_title("KNN vs. Best Alternative (gap annotated)")
        ax.legend(fontsize=8, loc="lower right")
        ax.set_axisbelow(True)
        fig.tight_layout()
        fig.savefig(f"{OUT_DIR}/fig_algo_knn_vs_rest.png")
        plt.close(fig)

print("Figures written to", OUT_DIR)
for f in sorted(os.listdir(OUT_DIR)):
    print("  ", f)

# print the numbers that go in the paper table
print("\n=== TABLE 4.4 NUMBERS (mean across exercises, %) ===")
for a in mean_cv.index:
    r = df[df.algorithm == a]
    print(f"{a:22s} acc={r.cv_accuracy.mean()*100:5.1f}  "
          f"P={r.precision.mean()*100:5.1f}  R={r.recall.mean()*100:5.1f}  "
          f"F1={r.f1.mean()*100:5.1f}")

print("\n=== per-exercise KNN vs others ===")
for ex in EX_ORDER:
    r = df[df.exercise == ex].set_index("algorithm")
    print(f"{ex}:")
    for a in algos:
        if a in r.index:
            print(f"   {a:22s} {r.loc[a,'cv_accuracy']:.3f}")
