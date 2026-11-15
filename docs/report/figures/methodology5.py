#!/usr/bin/env python3
"""Figure 3.1 of the November 2026 report: the incremental approach with the increments as Burrow was built.
Same drawing as chapters2/make_figures.py; output figures/v5/incremental.png."""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "chapters2"))
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from make_figures import arrow, INK, MID

def incremental():
    fig, ax = plt.subplots(figsize=(11.5, 6.6), dpi=220)
    ax.set_xlim(0, 11.5); ax.set_ylim(0, 6.6); ax.axis("off")
    arrow(ax, (0.45, 0.55), (11.3, 0.55)); arrow(ax, (0.45, 0.55), (0.45, 6.5))
    ax.text(5.9, 0.2, "Project timeline, June to November 2026", ha="center", style="italic", fontsize=11, color=INK)
    ax.text(0.2, 3.5, "System capability", va="center", rotation=90, style="italic", fontsize=11, color=INK)
    steps = [("Increment 1", "Memory in plain files", "Vault, index, search, links"),
             ("Increment 2", "Knowledge for a local model", "Engine steps, knowledge evaluation"),
             ("Increment 3", "Decisions kept", "Ledger, MCP server, hooks, app"),
             ("Increment 4", "Real workflows", "Reasons, check, handover, many tools"),
             ("Increment 5", "Kept to, safely", "Gate and verdicts, teams, security")]
    w, h = 1.55, 1.5
    for i, (name, green, below) in enumerate(steps):
        x = 0.85 + i * 2.12
        y = 0.95 + i * 0.82
        ax.add_patch(Rectangle((x, y), w, h, fc="white", ec=INK, lw=1.4, zorder=2))
        for j, (word, fill) in enumerate([("Analysis", "#f4f6fb"), ("Design", "#e3e9f5"), ("Build", MID), ("Evaluate", "#f4f6fb")]):
            yy = y + h - 0.14 - (j + 1) * 0.31
            ax.add_patch(Rectangle((x + 0.12, yy), w - 0.24, 0.27, fc=fill, ec="#9aa5bd", lw=0.8, zorder=3))
            ax.text(x + w / 2, yy + 0.135, word, ha="center", va="center", fontsize=9.5, color=INK, zorder=4)
        ax.text(x + w / 2, y + h + 0.52, name, ha="center", fontsize=12, weight="bold", style="italic", color=INK)
        ax.text(x + w / 2, y + h + 0.24, green, ha="center", fontsize=9.5, style="italic", color="#2d6a2d")
        arrow(ax, (x + w / 2, y + h), (x + w / 2, y + h + 0.18))
        ax.text(x + w / 2, y - 0.22, below, ha="center", fontsize=9.5, color=INK)
        if i < len(steps) - 1:
            arrow(ax, (x + w, y + h * 0.65), (x + 2.12, y + 0.82 + h * 0.45), color="#6b768f")
    fig.savefig(HERE / "v5" / "incremental.png", bbox_inches="tight", pad_inches=0.08, facecolor="white")
    plt.close(fig)

if __name__ == "__main__":
    incremental()
