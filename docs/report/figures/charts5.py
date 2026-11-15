#!/usr/bin/env python3
"""Result charts of Chapter 5 (November 2026 report). Every number is copied from the run records named beside it:
trials/stress/RESULTS.md, DECISIONS.md (D-99, D-102, D-108, D-110) and generated3/numbers.json. Output: v5/."""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
HERE = Path(__file__).parent
plt.rcParams.update({"font.family": ["Arial", "Helvetica", "DejaVu Sans"], "font.size": 8, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.edgecolor": "#777777", "axes.grid": True, "axes.axisbelow": True,
                     "grid.color": "#e4e4e4", "grid.linewidth": 0.6})
BASE, BURROW, MID = "#9aa5b1", "#1a9e77", "#7b61c4"

def save(f, name):
    f.tight_layout(); f.savefig(HERE / "v5" / f"{name}.png", dpi=300, facecolor="white"); plt.close(f)

def hbars(ax, rows, title, xmax=100):
    """rows: (label, right, total, colour). Bars show the percentage; the count is written beside each."""
    ys = list(range(len(rows)))[::-1]
    for y, (label, right, total, colour) in zip(ys, rows):
        pct = 100 * right / total
        ax.barh(y, pct, 0.62, color=colour, edgecolor="white")
        ax.text(pct + 1.5, y, f"{right} of {total}", va="center", fontsize=7.4, color="#111111")
    ax.set_yticks(ys); ax.set_yticklabels([r[0] for r in rows], fontsize=7.4)
    ax.set_xlim(0, xmax + 22); ax.set_xticks([0, 25, 50, 75, 100]); ax.grid(axis="y", visible=False)
    ax.set_title(title, fontsize=8.2, loc="left", weight="bold")

# Figure: keeping a decision, finding it, and carrying work on
f, axes = plt.subplots(2, 2, figsize=(6.4, 4.3))
hbars(axes[0][0], [("Reasons lost", 12, 15, BASE), ("Reasons kept", 9, 9, BURROW)],
      "a. Earlier decision kept (Claude Code)")
hbars(axes[0][1], [("Newest first", 12, 20, BASE), ("Vector search", 18, 20, MID),
                   ("By relevance", 19, 20, BURROW)], "b. Decision delivered, odd wording")
hbars(axes[1][0], [("Summary alone", 0, 12, BASE), ("With folds", 6, 6, BURROW)],
      "c. Exact error after compaction")
hbars(axes[1][1], [("Old handoff", 0, 4, BASE), ("New handoff", 3, 3, BURROW)],
      "d. Right step carried on (Gemma)")
for ax in axes[1]: ax.set_xlabel("Runs (%)")
save(f, "chart-keep")

# Figure: resume against a pasted transcript (Evaluation 3, both directions, 30 probes)
f, ax = plt.subplots(figsize=(6.2, 1.9))
hbars(ax, [("Nothing", 0, 30, BASE), ("Today's session tools", 6, 30, MID), ("Burrow's resume (about 1,800 tokens)", 11, 30, BURROW),
           ("The whole transcript pasted (2,400 to 6,300 tokens)", 18, 30, "#e0861a")], "Questions about the earlier session answered right")
ax.set_xlabel("Probes (%)")
save(f, "chart-resume")

# Figure: the check inside other programs (D-108)
f, ax = plt.subplots(figsize=(6.2, 2.5))
progs = ["Hermes Agent", "OpenCode", "OpenClaw"]
told = [(2, 2), (6, 6), (2, 2)]
undone = [(2, 2), (3, 6), (0, 2)]
ys = [2, 1, 0]
for y, (t, n), (u, m) in zip(ys, told, undone):
    ax.barh(y + 0.17, 100 * t / n, 0.32, color=MID, edgecolor="white")
    ax.text(100 * t / n + 1.5, y + 0.17, f"{t} of {n}", va="center", fontsize=7.2)
    ax.barh(y - 0.17, 100 * u / m, 0.32, color=BURROW, edgecolor="white")
    ax.text(100 * u / m + 1.5, y - 0.17, f"{u} of {m}", va="center", fontsize=7.2)
ax.set_yticks(ys); ax.set_yticklabels(progs); ax.set_xlim(0, 122); ax.grid(axis="y", visible=False)
ax.barh([-5], [0], color=MID, label="Told the person which decision and why")
ax.barh([-5], [0], color=BURROW, label="Put the code back")
ax.set_ylim(-0.6, 2.6); ax.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.45, -0.3), ncols=2, fontsize=7)
ax.set_xlabel("Runs in which the model edited the decision's code (%)")
save(f, "chart-gate")
print("charts written")
