#!/usr/bin/env python3
"""Draws the conceptual framework of Section 2.5 as an input, processing, output flow of the system.
Icons are macOS system symbols rendered by icons/render_icons.swift. Output: v5/framework.png (November 2026 framing)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
W, H = 2400, 3040
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)
A = "/System/Library/Fonts/Supplemental/Arial.ttf"
AB = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
AI = "/System/Library/Fonts/Supplemental/Arial Italic.ttf"
def f(size, face=A): return ImageFont.truetype(face, size)

BLUE, BLUE_BG, BLUE_LINE = "#1D4ED8", "#EFF6FF", "#93C5FD"
PURPLE, PURPLE_BG, PURPLE_LINE = "#6D28D9", "#F5F3FF", "#C4B5FD"
TEAL = "#0F766E"
GREEN, GREEN_BG, GREEN_LINE = "#15803D", "#F0FDF4", "#86EFAC"
ORANGE = "#C2410C"
GREY, GREY_BG, INK, SOFT = "#64748B", "#F8FAFC", "#0F172A", "#334155"
STAGE = ["#7C3AED", "#6D28D9", "#0F766E", "#5B21B6", "#4C1D95"]

def icon(name, colour, box, size):
    im = Image.open(HERE / "icons" / f"{name}-{colour}.png").convert("RGBA")
    scale = size / max(im.size)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    x, y = box
    img.paste(im, (int(x - im.width / 2), int(y - im.height / 2)), im)

def wrap(text, font, width):
    lines = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            trial = (line + " " + word).strip()
            if d.textlength(trial, font=font) <= width: line = trial
            else:
                lines.append(line); line = word
        lines.append(line)
    return lines

def text(x, y, words, font, fill=INK, width=None, gap=1.28, anchor="l"):
    lines = wrap(words, font, width) if width else words.split("\n")
    step = int(font.size * gap)
    for i, line in enumerate(lines):
        if anchor == "m": d.text((x, y + i * step), line, font=font, fill=fill, anchor="ma")
        else: d.text((x, y + i * step), line, font=font, fill=fill)
    return y + len(lines) * step

def box(xy, fill, line, radius=28, width=5, dash=False):
    if not dash:
        d.rounded_rectangle(xy, radius=radius, fill=fill, outline=line, width=width); return
    d.rounded_rectangle(xy, radius=radius, fill=fill)
    x0, y0, x1, y1 = xy
    for (a, b, c, e) in ((x0, y0, x1, y0), (x0, y1, x1, y1), (x0, y0, x0, y1), (x1, y0, x1, y1)):
        length = max(abs(c - a), abs(e - b)); n = int(length // 36)
        for i in range(n + 1):
            t0, t1 = i * 36, min(i * 36 + 20, length)
            if a == c: d.line((a, b + t0, a, b + t1), fill=line, width=width)
            else: d.line((a + t0, b, a + t1, b), fill=line, width=width)

def arrow(points, colour, width=9, head=30, dash=False, both=False):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if dash:
            length = max(abs(x1 - x0), abs(y1 - y0)); n = int(length // 40)
            for i in range(n + 1):
                t0, t1 = i * 40, min(i * 40 + 24, length)
                if x0 == x1:
                    s = 1 if y1 > y0 else -1; d.line((x0, y0 + s * t0, x0, y0 + s * t1), fill=colour, width=width)
                else:
                    s = 1 if x1 > x0 else -1; d.line((x0 + s * t0, y0, x0 + s * t1, y0), fill=colour, width=width)
        else:
            d.line((x0, y0, x1, y1), fill=colour, width=width)
    def tip(p, q):
        (x0, y0), (x1, y1) = p, q
        if x0 == x1:
            s = 1 if y1 > y0 else -1
            d.polygon([(x1, y1 + s * 4), (x1 - head * 0.62, y1 - s * head), (x1 + head * 0.62, y1 - s * head)], fill=colour)
        else:
            s = 1 if x1 > x0 else -1
            d.polygon([(x1 + s * 4, y1), (x1 - s * head, y1 - head * 0.62), (x1 - s * head, y1 + head * 0.62)], fill=colour)
    tip(points[-2], points[-1])
    if both: tip(points[1], points[0])

def pill(x, y, words, colour):
    font = f(46, AB); w = d.textlength(words, font=font) + 64
    d.rounded_rectangle((x, y, x + w, y + 74), radius=37, fill=colour)
    d.text((x + 32, y + 12), words, font=font, fill="white")

# Title
text(W / 2, 34, "Burrow: one memory of decisions for every AI tool", f(60, AB), anchor="m")
text(W / 2, 112, "The vault, the Ledger and the engine run on the person's own Mac; any local or cloud AI tool connects to it", f(40, AI), fill=SOFT, anchor="m")

# INPUT
pill(60, 190, "1  INPUT", BLUE)
box((60, 286, 1130, 700), BLUE_BG, BLUE_LINE)
icon("person.fill", "1D4ED8", (160, 380), 110); icon("bubble.left.and.bubble.right.fill", "1D4ED8", (160, 560), 120)
text(250, 318, "Work with AI tools", f(54, AB), fill=BLUE)
text(250, 392, "A decision settled with one tool: “Match payments by account reference only, never by phone and amount.”", f(40), width=850)
text(250, 584, "Later: another tool, another session.", f(40, AI), fill=SOFT, width=850)

box((1210, 286, 2250, 700), BLUE_BG, BLUE_LINE)
icon("folder.fill", "1D4ED8", (1310, 390), 125); icon("doc.text.fill", "1D4ED8", (1310, 560), 100)
text(1400, 318, "The person's material", f(54, AB), fill=BLUE)
text(1400, 396, "Notes and documents in Markdown, and code folders linked in read-only, kept as plain files on the Mac.", f(42), width=830)

# PROCESSING
pill(60, 790, "2  PROCESSING: the Burrow engine", PURPLE)
box((60, 886, 2250, 2170), PURPLE_BG, PURPLE_LINE, radius=36)
stages = [
    ("Keep", "tray.and.arrow.down.fill", "The tool keeps the decision with its reason, what was rejected and the files it rests on, signed by the program."),
    ("Hand over", "arrow.left.arrow.right", "Every tool that connects gets the decisions in force; a resume says where work stopped."),
    ("Watch", "eye.fill", "A decision whose file changed is marked to check again; a new decision that contradicts an old one is caught."),
    ("Check", "checkmark.shield.fill", "Before work is done, the change is judged against each decision it touches, and held until it has been shown."),
    ("Share", "person.2.fill", "With the person's approval, a decision goes to a team folder that teammates' tools also read."),
]
rows = []
for i, (name, sym, words) in enumerate(stages):
    y0 = 930 + i * 244
    box((100, y0, 1340, y0 + 214), "white", STAGE[i], radius=24, width=6)
    d.rounded_rectangle((100, y0, 300, y0 + 214), radius=24, fill=STAGE[i])
    d.rectangle((270, y0, 300, y0 + 214), fill=STAGE[i])
    icon(sym, "FFFFFF", (200, y0 + 82), 96)
    d.text((200, y0 + 150), f"Step {i + 1}", font=f(36, AB), fill="white", anchor="ma")
    text(332, y0 + 16, name, f(52, AB), fill=STAGE[i])
    text(332, y0 + 82, words, f(37), width=985, gap=1.22)
    rows.append(y0 + 107)
for a, b in zip(rows, rows[1:]):
    arrow([(720, a + 107), (720, b - 107)], PURPLE, width=8, head=24)

# The Ledger and the index, beside Keep and Hand over
box((1500, 930, 2200, 1150), "white", PURPLE_LINE, radius=24)
icon("books.vertical.fill", "6D28D9", (1580, 1040), 96)
text(1660, 956, "The Ledger", f(44, AB), fill=PURPLE)
text(1660, 1014, "Plain files, never changed or deleted: a later commit retires an earlier one.", f(34), fill=SOFT, width=520)
arrow([(1340, rows[0]), (1500, rows[0])], PURPLE, width=8, head=24, both=True)
box((1500, rows[1] - 70, 2200, rows[1] + 70), "white", PURPLE_LINE, radius=24)
icon("cylinder.split.1x2.fill", "6D28D9", (1580, rows[1]), 90)
text(1660, rows[1] - 48, "Rebuildable index", f(42, AB), fill=PURPLE)
text(1660, rows[1] + 6, "SQLite: words, vectors, links", f(36), fill=SOFT)
arrow([(1340, rows[1]), (1500, rows[1])], PURPLE, width=8, head=24, both=True)

# The AI tools, beside Hand over and Check
box((1500, 1380, 2200, 1900), TEAL, TEAL, radius=30)
icon("terminal.fill", "FFFFFF", (1850, 1480), 140)
text(1850, 1572, "Any AI tool, local or cloud", f(46, AB), fill="white", anchor="m")
text(1850, 1640, "Claude Code, OpenCode, OpenClaw,", f(38), fill="white", anchor="m")
text(1850, 1690, "Hermes, n8n, llama.cpp", f(38), fill="white", anchor="m")
icon("lock.fill", "FFFFFF", (1620, 1812), 56)
text(1670, 1788, "Connects over MCP", f(38, AB), fill="white")
arrow([(1340, rows[3] - 20), (1500, rows[3] - 20)], TEAL, width=9, both=True)
text(1420, rows[3] - 90, "MCP", f(34, AI), fill=TEAL, anchor="m")

text(1530, 1960, "Burrow calls no cloud model: only the local model service, for search by meaning.", f(34), fill=SOFT, width=680)

# OUTPUT
pill(60, 2254, "3  OUTPUT", GREEN)
outs = [
    ("hand.raised.fill", "The decision kept", "The next tool keeps to it, or names it and asks the person.",
     "“I haven't made this change. It goes against the decision on group payments.”"),
    ("arrow.forward", "Work carried on", "A different tool picks up the right step, with the constraint and the last error.",
     "“Carry on where the last session stopped.”"),
    ("checkmark", "A verdict on the change", "Breaks, affected or unaffected, for each decision the change touches.",
     "A change that breaks a decision is held until it is undone or overturned."),
]
for i, (sym, name, words, example) in enumerate(outs):
    x0 = 60 + i * 740
    box((x0, 2350, x0 + 710, 2770), GREEN_BG, GREEN_LINE)
    icon(sym, "15803D", (x0 + 80, 2428), 92)
    text(x0 + 150, 2386, name, f(46, AB), fill=GREEN)
    y = text(x0 + 36, 2490, words, f(38), width=640, gap=1.22)
    text(x0 + 36, y + 14, example, f(34, AI), fill=SOFT, width=640, gap=1.22)

arrow([(1040, 700), (1040, 886)], BLUE, width=12, head=36)
arrow([(1730, 700), (1730, 886)], BLUE, width=12, head=36)
arrow([(480, 2170), (480, 2350)], GREEN, width=12, head=36)
arrow([(1155, 2170), (1155, 2350)], GREEN, width=12, head=36)
arrow([(1895, 2170), (1895, 2350)], GREEN, width=12, head=36)

# Feedback: new decisions return to the Ledger
arrow([(2250, 2560), (2340, 2560), (2340, 493), (2250, 493)], ORANGE, width=10, head=34, dash=True)
label = Image.new("RGBA", (1200, 60), (255, 255, 255, 0))
ImageDraw.Draw(label).text((600, 4), "FEEDBACK: each new decision joins the Ledger", font=f(40, AB), fill=ORANGE, anchor="ma")
label = label.rotate(90, expand=True)
img.paste(label, (2346, 900), label)

box((60, 2840, 1130, 3010), GREY_BG, GREY, dash=True, width=5)
icon("cloud.fill", "64748B", (150, 2925), 110)
text(230, 2862, "Compared with: no memory, a pasted transcript,", f(38, AB), fill=SOFT)
text(230, 2918, "plain vector search, and Burrow before each fix. Not part of the engine.", f(34), fill=SOFT, width=870, gap=1.2)
box((1210, 2840, 2250, 3010), GREY_BG, GREY, width=5)
icon("chart.bar.fill", "334155", (1300, 2925), 100)
text(1380, 2862, "Measured on every run", f(40, AB), fill=SOFT)
text(1380, 2918, "Material found, decision kept (hidden tests), work carried on, verdict right, seconds.", f(34), fill=SOFT, width=840, gap=1.2)
arrow([(1130, 2925), (1210, 2925)], GREY, width=8, head=24)

(HERE / "v5").mkdir(exist_ok=True)
img.save(HERE / "v5" / "framework.png", dpi=(380, 380))
print("saved", img.size)
