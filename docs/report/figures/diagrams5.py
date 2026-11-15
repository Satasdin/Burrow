#!/usr/bin/env python3
"""Chapter 4 diagrams of the November 2026 report, for Burrow as built on 15 November 2026: the Ledger, the
connection to AI tools, the check of new work, and sharing within a team. Same hand-placed grid and notation as
diagrams2.py (one unit is 0.01 inch; 626 is the printed text width). Output goes to figures/v5.
Run: python3 docs/report/figures/diagrams5.py [name ...]"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse

from diagrams import INK, SIZE, component, node
from diagrams2 import SMALL, Sheet as Sheet2, _frame, _lifelines, _message, _self, act, _window

OUT = Path(__file__).parent / "v5"


class Sheet(Sheet2):
    def save(self):
        OUT.mkdir(exist_ok=True)
        self.figure.savefig(OUT / f"{self.name}.png", dpi=300, facecolor="white")
        plt.close(self.figure)

    def dot(self, x, y, r=3.2, filled=False):
        self.ax.add_patch(Ellipse((x, y), 2 * r, 2 * r, facecolor=INK if filled else "white", edgecolor=INK, lw=0.7, zorder=5))


# ---------------------------------------------------------------- analysis

def use_cases():
    s = Sheet("use_cases", 626, 520)
    s.rect(118, 8, 390, 504, line=0.9, z=1)
    s.text(313, 22, "Burrow", weight="bold", size=8.4)
    L, R, W, H = 214, 412, 150, 42
    left = [(66, "Open a vault and\nlink code folders"), (146, "Search and ask\nthe vault"), (226, "Review the Ledger:\nconfirm or mark wrong"),
            (306, "Approve linked folders,\nshares and overrides"), (386, "Share a decision\nwith a team")]
    right = [(66, "Find and read\nmaterial"), (146, "Attach the decisions\nthat fit the request"), (226, "Resume earlier\nwork"),
             (306, "Keep a decision\nwith its reason"), (386, "Check a change\nagainst decisions"), (466, "Hold the change")]
    for y, words in left:
        s.ellipse(L, y, W, H, words)
    for y, words in right:
        s.ellipse(R, y, W, H, words)
    # The person.
    person = (52, 230)
    s.actor(*person, "Person")
    for y, _ in left:
        s.line([(person[0] + 16, person[1] - 8), (L - W / 2, y)])
    # A teammate receives what is shared.
    s.actor(52, 470, "Teammate")
    s.line([(68, 462), (L - 40, 402)])
    # AI tool on the right.
    tool = (576, 250)
    s.actor(*tool, "AI tool")
    for y in (66, 226, 306, 386):
        s.line([(tool[0] - 16, tool[1] - 8), (R + W / 2, y)])
    # Local model service, used to search by meaning.
    s.actor(576, 52, "Local model\nservice")
    s.line([(560, 46), (R + W / 2, 62)])
    # Includes and the extension.
    s.line([(R, 87), (R, 125)], "open", dashed=True)
    s.text(R + 28, 106, "«include»", size=SMALL, back=True)
    s.line([(R, 205), (R, 167)], "open", dashed=True)
    s.text(R + 28, 186, "«include»", size=SMALL, back=True)
    s.line([(R, 445), (R, 407)], "open", dashed=True)
    s.text(R + 28, 426, "«extend»", size=SMALL, back=True)
    s.note(R - 190, 452, 84, 28, "[a decision is\ntouched, not shown]", size=6.0)
    s.line([(R - 106, 466), (R - W / 2, 466)], dashed=True, lw=0.5)
    s.save()


def sequence_session():
    s = Sheet("sequence_session", 626, 700)
    P, T, M, LG, IX = 40, 156, 300, 444, 572
    _lifelines(s, [(P, ":Person"), (T, ":AI tool"), (M, ":burrow mcp"), (LG, ":Ledger"), (IX, ":Index")], 690, half=40)
    for x, a, b in [(T, 58, 680), (M, 76, 96), (M, 116, 168), (LG, 130, 156), (M, 196, 290), (IX, 210, 234), (LG, 252, 276),
                    (M, 348, 438), (LG, 362, 386), (M, 590, 634), (LG, 604, 622)]:
        s.rect(x - 4, a, 8, b - a, z=4)
    _message(s, P, T - 4, 62, "\"carry on the payments task\"")
    _message(s, T + 4, M - 4, 80, "initialize")
    _message(s, M - 4, T + 4, 96, "tools; decisions in force", True)
    _message(s, T + 4, M - 4, 120, "burrow_resume")
    _message(s, M + 4, LG - 4, 134, "resume(branch)")
    _message(s, LG - 4, M + 4, 154, "plan, last handoff, decisions", True)
    _message(s, M - 4, T + 4, 168, "where it stopped, with reasons", True)
    _message(s, T + 4, M - 4, 200, "burrow_find(request)")
    _message(s, M + 4, IX - 4, 214, "rank by words and meaning")
    _message(s, IX - 4, M + 4, 232, "excerpts with file:line", True)
    _message(s, M + 4, LG - 4, 256, "notes(for: request, files)")
    _message(s, LG - 4, M + 4, 274, "decisions that fit", True)
    _message(s, M - 4, T + 4, 290, "excerpts and decisions", True)
    _self(s, T, 306, "edit the linked code", drop=18)
    _message(s, T + 4, M - 4, 352, "burrow_check")
    _message(s, M + 4, LG - 4, 366, "decisions on changed files")
    _message(s, LG - 4, M + 4, 384, "decisions", True)
    _self(s, M, 396, "judge each decision:\nbreaks, affected, unaffected", drop=20)
    _message(s, M - 4, T + 4, 436, "diff beside decisions, verdicts", True)
    _frame(s, 12, 452, 608, 196, "alt", "[the change goes against a decision]", T + 12)
    _message(s, T - 4, P, 490, "names the decision, asks")
    _message(s, P, T - 4, 524, "\"undo it\"", True)
    _self(s, T, 536, "put the code back", drop=14)
    s.line([(12, 566), (620, 566)], dashed=True, lw=0.6)
    s.text(T + 12, 576, "[the change keeps to every decision, and the person settles something new]", ha="left", size=7.2)
    _message(s, T + 4, M - 4, 594, "burrow_commit(decision, because, rejected, files)")
    _message(s, M + 4, LG - 4, 608, "commit")
    _message(s, LG - 4, M + 4, 622, "id", True)
    _message(s, M - 4, T + 4, 634, "Kept as decision <id>", True)
    _message(s, T - 4, P, 670, "done, with the decision kept", True)
    s.save()


def activity_check():
    s = Sheet("activity_check", 626, 790)
    s.rect(4, 6, 618, 778, z=1)
    s.line([(184, 6), (184, 784)])
    s.line([(444, 6), (444, 784)])
    s.line([(4, 28), (622, 28)])
    for x, words in [(94, "AI tool"), (314, "Burrow (check and gate)"), (533, "Person")]:
        s.text(x, 17, words, weight="bold", size=8.2)
    A, B, C, RAIL = 94, 300, 533, 392
    s.start(A, 46)
    act(s, A, 90, "Edit the linked code", w=150, h=30)
    s.line([(A, 53), (A, 75)], "fill")
    act(s, A, 146, "Try to finish: burrow_check,\nend of turn, or git commit", w=160)
    s.line([(A, 105), (A, 127)], "fill")
    act(s, B, 146, "Read what changed since\nthe last git commit", w=180)
    s.line([(A + 80, 146), (B - 90, 146)], "fill")
    act(s, B, 204, "Find decisions resting on the\nchanged files or one import away", w=200)
    s.line([(B, 165), (B, 185)], "fill")
    s.diamond(B, 258)
    s.line([(B, 223), (B, 243)], "fill")
    s.text(B + 20, 249, "[none]", size=SMALL, ha="left")
    s.text(B - 8, 284, "[some]", size=SMALL, ha="right")
    act(s, B, 318, "Judge each decision: run the\nperson's check, compare parts", w=200)
    s.line([(B, 273), (B, 299)], "fill")
    s.diamond(B, 376)
    s.line([(B, 337), (B, 361)], "fill")
    s.text(B + 20, 367, "[unaffected]", size=SMALL, ha="left")
    s.text(B - 20, 367, "[breaks]", size=SMALL, ha="right")
    s.text(B + 6, 406, "[affected or\nunprovable]", size=SMALL, ha="left")
    s.diamond(B, 446)
    s.line([(B, 391), (B, 431)], "fill")
    s.text(B + 20, 437, "[shown before]", size=SMALL, ha="left")
    s.text(B + 6, 474, "[not shown]", size=SMALL, ha="left")
    act(s, B, 528, "Hold the change: show each decision\nwith its reason, and a failing check", w=210)
    s.line([(B, 461), (B, 509)], "fill")
    s.line([(B - 15, 376), (214, 376), (214, 509)], "fill")
    # The rail of changes that pass.
    s.line([(B + 15, 258), (RAIL, 258), (RAIL, 705)], "fill")
    s.line([(B + 15, 376), (RAIL, 376)])
    s.line([(B + 15, 446), (RAIL, 446)])
    # The tool answers for a held change.
    act(s, A, 528, "Tell the person which\ndecision and why", w=150)
    s.line([(B - 105, 528), (A + 75, 528)], "fill")
    s.diamond(A, 598)
    s.line([(A, 547), (A, 583)], "fill")
    s.text(A - 8, 626, "[keep the\ndecision]", size=SMALL, ha="right")
    act(s, A, 660, "Undo the part that\ngoes against it", w=150)
    s.line([(A, 613), (A, 641)], "fill")
    s.text(A + 22, 590, "[the person overturns it]", size=SMALL, ha="left")
    act(s, C, 598, "Overturn the decision,\nwith a one-time code\nfrom a notification", w=150, h=46)
    s.line([(A + 15, 598), (C - 75, 598)], "fill")
    s.diamond(RAIL, 720)
    s.line([(A, 679), (A, 720), (RAIL - 15, 720)], "fill")
    s.line([(C, 621), (C, 720), (RAIL + 15, 720)], "fill")
    act(s, RAIL, 752, "Let it through", w=110, h=24)
    s.line([(RAIL, 735), (RAIL, 740)], "fill")
    s.stop(RAIL - 82, 752)
    s.line([(RAIL - 55, 752), (RAIL - 73, 752)], "fill")
    s.save()


def classes():
    s = Sheet("classes", 626, 620)

    def cls(x, y, w, name, fields, methods, stereotype=None, size=6.9):
        head = 22 if not stereotype else 34
        h = head + 11.5 * len(fields) + 6 + (11.5 * len(methods) + 6 if methods else 0)
        s.rect(x, y, w, h, z=2)
        if stereotype:
            s.text(x + w / 2, y + 10, stereotype, size=7.0)
            s.text(x + w / 2, y + 23, name, weight="bold")
        else:
            s.text(x + w / 2, y + 11, name, weight="bold")
        s.line([(x, y + head), (x + w, y + head)])
        for i, field in enumerate(fields):
            s.text(x + 5, y + head + 9 + 11.5 * i, field, ha="left", size=size)
        if methods:
            sep = y + head + 11.5 * len(fields) + 6
            s.line([(x, sep), (x + w, sep)])
            for i, method in enumerate(methods):
                s.text(x + 5, sep + 9 + 11.5 * i, method, ha="left", size=size)
        return h

    def lab(x, y, words, ha="center"):
        s.text(x, y, words, size=6.6, ha=ha)

    # Row 1: the server, the tools, the vault.
    cls(6, 8, 128, "MCPServer", ["tools : ToolSet", "client : String?"], ["serve()", "handle(request)"])
    cls(196, 8, 180, "VaultTools", ["vault : Vault", "ledger : Ledger", "sessions : SessionStore"],
        ["call(name, arguments) : ToolResult", "check() : CheckReport"])
    cls(436, 8, 184, "Vault", ["root : URL", "store : URL"], ["refresh() : IndexReport", "retrieve(request) : Retrieved", "approvedFolders() : [URL]"])
    s.line([(134, 40), (196, 40)], "open"); lab(186, 33, "1")
    s.line([(376, 40), (436, 40)], "open"); lab(428, 33, "1")
    # Row 2: the Ledger, its commits and their kinds.
    cls(6, 140, 200, "Ledger", ["folder : URL", "branch : String"],
        ["commit(kind, message, files)", "revert(id, why)", "confirm(id)", "resume(branch) : String", "notes(for request)", "staleness(of commit)"])
    s.line([(222, 100), (222, 120), (106, 120), (106, 140)], "open"); lab(112, 132, "1", "left")
    cls(262, 140, 176, "LedgerCommit", ["id, branch : String", "parent : String?", "kind : Kind", "message, body : String",
                                        "author, client : String", "person : String?", "cites : [path : hash]", "reverts : String?",
                                        "session : String?"], [])
    s.line([(206, 180), (262, 180)], "open"); lab(214, 173, "1"); lab(250, 173, "0..*")
    cls(492, 140, 128, "Kind", ["decision", "fact", "correction", "plan", "handoff", "code", "confirmation"], [], "«enumeration»")
    s.line([(438, 180), (492, 180)], "open"); lab(484, 173, "1")
    s.line([(438, 240), (458, 240), (458, 292), (404, 292), (404, 273)], "open")
    lab(462, 282, "reverts 0..1", "left")
    # Row 3: sessions and folds, the check and its verdicts, teams.
    cls(6, 330, 150, "SessionRecord", ["id : String", "client : String?", "trail : [TrailStep]", "request : String?"], [])
    s.line([(40, 266), (40, 330)], "open"); lab(46, 300, "commits name\ntheir session", "left")
    cls(6, 440, 150, "Fold", ["session : String", "number : Int", "event : String", "asked, errors : [Quote]"], [])
    s.line([(81, 404), (81, 440)]); lab(87, 414, "1", "left"); lab(87, 432, "0..*", "left")
    cls(196, 330, 160, "CheckReport", ["changed : [String]", "rules : [LedgerCommit]", "verdicts : [DecisionVerdict]"], [])
    s.line([(300, 330), (300, 273)], "open"); lab(306, 300, "rules 0..*", "left")
    cls(196, 430, 160, "DecisionVerdict", ["decision : String", "kind : VerdictKind", "touched : [String]"], [])
    s.line([(276, 393), (276, 430)], "open"); lab(282, 420, "0..*", "left")
    cls(196, 524, 160, "VerdictKind", ["breaks, affected,", "unaffected, unprovable"], [], "«enumeration»")
    s.line([(276, 493), (276, 524)], "open"); lab(282, 514, "1", "left")
    cls(396, 430, 124, "DecisionCheck", ["kind : command | forbid", "written : String", "by : String"], [])
    s.line([(356, 460), (396, 460)], "open"); lab(388, 453, "0..1")
    cls(396, 330, 104, "Team", ["name : String", "path : String"], ["ledger() : Ledger"])
    cls(520, 330, 100, "PendingShare", ["id : String", "message : String", "by : String"], [])
    s.line([(500, 360), (520, 360)], "open"); lab(510, 353, "0..*")
    s.save()


# ---------------------------------------------------------------- design

def architecture():
    s = Sheet("architecture", 626, 480)
    s.text(8, 12, "AI programs on this Mac", ha="left", size=SMALL, style="italic")
    progs = [(8, "Claude Code"), (130, "OpenCode"), (252, "OpenClaw,\nHermes Agent"), (374, "n8n (through\na bridge)"), (496, "llama.cpp\nserver page")]
    for x, words in progs:
        s.rect(x, 22, 114, 36, words)
    s.text(8, 76, "Interfaces", ha="left", size=SMALL, style="italic")
    faces = [(8, 150, "burrow mcp\nMCP server, stdio"), (166, 148, "Hooks and gates\nStop, pre-commit, plugins"),
             (322, 140, "burrow\ncommand line"), (470, 148, "Burrow.app\ndesktop app")]
    for x, w, words in faces:
        component(s, x, 86, w, 44, words)
    s.line([(65, 58), (65, 70), (553, 70), (553, 58)], lw=0.7)
    for x in (187, 309, 431):
        s.line([(x, 58), (x, 70)], lw=0.7)
    s.line([(83, 70), (83, 86)], "open")
    s.text(90, 78, "MCP, stdio", size=6.4, ha="left", back=True)
    s.line([(240, 70), (240, 86)], "open", dashed=True)
    s.text(246, 78, "hooks, on finishing", size=6.4, ha="left", back=True)
    # The engine.
    s.rect(8, 160, 610, 220, z=1)
    s.text(16, 173, "«component»  BurrowTools", ha="left", weight="bold")
    tools = [(18, "Ledger\ncommits, branches,\nresume, staleness"), (138, "Sessions and folds\ntrails, handoffs,\nexact words"),
             (258, "Check and verdicts\ndiff, decisions,\nperson's checks"), (378, "Guards\nsecrets, steering\ntext, presence"),
             (498, "Team sharing\nteam Ledger,\npending shares")]
    for x, words in tools:
        s.rect(x, 184, 110, 58, words, z=3, size=7.0)
    s.text(16, 262, "«component»  BurrowCore", ha="left", weight="bold")
    core = [(18, "Vault and index\nsearch by words\nand meaning, links"), (138, "Link approvals\nfolders followed\nonly once allowed"),
            (258, "Bridges\none-way reading\nof another vault"), (378, "Storage limits\nper vault and\noverall"),
            (498, "Ollama client\nembeddings,\nlocal answers")]
    for x, words in core:
        s.rect(x, 274, 110, 58, words, z=3, size=7.0)
    s.text(313, 360, "One Swift package, no third-party dependency", size=SMALL, style="italic")
    for x in (83, 241, 396, 544):
        s.line([(x, 130), (x, 160)], "open", dashed=True)
    # Stores, and the one service Burrow calls.
    stores = [(18, "Vault folder\nnotes, documents;\nlinked code, read-only"), (138, ".burrow in the vault\nindex.sqlite, vectors,\nledger/, sessions/"),
              (258, "Burrow's own folder\napprovals, folds,\nbridges (owner only)"), (378, "Team folder\na git repository or\na synced folder"),
              (498, "Ollama\n127.0.0.1:11434\n(HTTP, loopback)")]
    for x, words in stores:
        s.rect(x, 410, 110, 58, words, size=7.0)
    for x in (73, 193, 313, 433, 553):
        s.line([(x, 380), (x, 410)], "open", dashed=True)
    s.save()


def schema():
    s = Sheet("schema", 626, 420)

    def table(x, y, w, name, rows, dashed=False):
        h = 22 + 14 * len(rows) + 6
        s.rect(x, y, w, h, dashed=dashed, z=2)
        s.rect(x, y, w, 22, name, weight="bold", dashed=dashed, z=3)
        for i, row in enumerate(rows):
            s.text(x + 6, y + 33 + 14 * i, row, ha="left", size=7.0)
        return h

    table(8, 10, 182, "LedgerCommit  (Markdown file)", ["PK  id", "FK  parent → LedgerCommit.id", "FK  reverts → LedgerCommit.id",
                                                             "FK  session → Session.id", "      branch, kind, at", "      author, client, person",
                                                             "      message, Because, Rejected", "      cites: path → content hash", "      overlaps"])
    table(244, 10, 150, "Session  (JSON file)", ["PK  id", "FK  resumedFrom → Session.id", "      client, started, updated", "      trail: lookups, reads,", "      commits, checks", "      request"])
    table(448, 10, 170, "Fold  (in Burrow's own folder)", ["PK  id", "FK  session → Session.id", "      number, event, at", "      asked, reasons, errors,", "      places, files, commands"])
    table(8, 230, 140, "files", ["PK  id", "      path (unique)", "      hash, is_note"])
    table(196, 230, 140, "chunks", ["PK  id", "FK  file_id → files.id", "      start_line, end_line", "      body"])
    table(384, 230, 110, "vectors", ["PK, FK  chunk_id", "      vector"])
    table(196, 340, 140, "links", ["PK  source, target, kind", "      via"])
    table(512, 230, 106, "Check  (JSON)", ["PK  fingerprint", "      decisions shown", "      file blob ids", "      shown by"], dashed=False)
    # Relationships with cardinalities.
    s.line([(190, 60), (244, 60)]); s.text(198, 53, "0..*", size=7); s.text(236, 53, "0..1", size=7)
    s.line([(394, 60), (448, 60)]); s.text(402, 53, "1", size=7); s.text(436, 53, "0..*", size=7)
    s.line([(148, 260), (196, 260)]); s.text(156, 253, "1", size=7); s.text(186, 253, "0..*", size=7)
    s.line([(336, 260), (384, 260)]); s.text(344, 253, "1", size=7); s.text(374, 253, "0..1", size=7)
    s.line([(78, 167), (78, 230)], dashed=True); s.text(84, 178, "0..*", size=7, ha="left"); s.text(84, 222, "0..*", size=7, ha="left")
    s.text(72, 199, "cites, by path", size=6.8, ha="right")
    s.line([(78, 300), (78, 368), (196, 368)], dashed=True); s.text(84, 340, "links between\nfiles, by path", size=6.8, ha="left")
    s.line([(150, 167), (150, 196), (565, 196), (565, 230)], dashed=True); s.text(360, 190, "decisions shown, by id", size=6.8)
    s.rect(384, 330, 234, 80, dashed=True)
    s.text(392, 342, "Index: SQLite file .burrow/index.sqlite, rebuilt", ha="left", size=6.8)
    s.text(392, 356, "from the vault if deleted. Ledger, sessions and", ha="left", size=6.8)
    s.text(392, 370, "checks: plain files in .burrow, readable in any", ha="left", size=6.8)
    s.text(392, 384, "editor. A commit is never changed or deleted; a", ha="left", size=6.8)
    s.text(392, 398, "later commit retires it.", ha="left", size=6.8)
    s.save()


def deployment():
    s = Sheet("deployment", 626, 450)
    node(s, 8, 24, 452, 414, "«device» The person's Mac (Apple silicon)")
    s.rect(24, 64, 130, 46, "«process»\nAI program, for example\nClaude Code or OpenCode", z=3, size=6.8)
    s.rect(182, 64, 116, 46, "«process»\nburrow mcp\n(one per program)", z=3, size=7.0)
    s.rect(326, 64, 118, 46, "«artifact»\nBurrow.app", z=3, size=7.2)
    s.line([(154, 87), (182, 87)], "open")
    s.text(168, 122, "stdio,\nJSON-RPC", size=6.4)
    # Ollama, on the loopback address only.
    s.rect(250, 150, 194, 96, z=2)
    s.text(258, 162, "«service» Ollama, 127.0.0.1", ha="left", size=7.2)
    s.rect(258, 176, 86, 60, "chat model\n(Gemma 4 12B,\nQwen3 4B)", z=3, size=6.8)
    s.rect(352, 176, 84, 60, "embedding\nmodel (Qwen3\nEmbedding)", z=3, size=6.8)
    s.line([(282, 110), (282, 150)], "open")
    s.line([(400, 110), (400, 150)], "open")
    s.text(341, 132, "HTTP", size=6.4)
    # Data on disk.
    s.rect(24, 280, 420, 138, z=2)
    s.text(32, 292, "Data on disk", ha="left", size=7.2)
    s.rect(32, 304, 130, 104, "Vault folder\nnotes and documents;\n.burrow: index,\nLedger, sessions", z=3, size=6.8)
    s.rect(170, 304, 130, 104, "Burrow's own folder\n(owner only):\napprovals, folds,\nbridges", z=3, size=6.8)
    s.rect(308, 304, 128, 104, "Team folder\n(git clone or\nsynced folder)", z=3, size=6.8)
    s.line([(210, 110), (210, 280)], "open", dashed=True)
    s.text(204, 196, "reads and\nwrites", size=6.4, ha="right")
    s.line([(444, 98), (452, 98), (452, 300), (444, 300)], "open", dashed=True)
    # Outside the Mac.
    node(s, 480, 24, 134, 112, "«cloud» Model provider")
    s.text(547, 92, "Cloud model API:\nused by cloud AI\nprograms, never\nby Burrow", size=6.8)
    s.line([(89, 64), (89, 46), (480, 46)], "open", dashed=True)
    s.text(300, 40, "HTTPS (cloud AI programs only)", size=6.4)
    node(s, 480, 170, 134, 112, "«cloud» Git host or sync")
    s.text(547, 236, "Team remote:\ndecisions shared\nafter approval", size=6.8)
    s.line([(436, 356), (468, 356), (468, 240), (480, 240)], "open", dashed=True)
    node(s, 480, 316, 134, 112, "«cloud» GitHub")
    s.text(547, 380, "Releases: the program,\nthe app and a\nchecksummed installer\nPages: project site\nover HTTPS", size=6.5)
    s.save()


# ---------------------------------------------------------------- wireframes

RIBBON = ["All", "Conv.", "Ledger", "Library", "Programs", "Map"]


def _chrome(s, bottom, chosen):
    _window(s, 8, 8, 610, bottom)
    s.text(96, 21, "New   Hide sidebar", size=SMALL)
    s.text(300, 21, "Back  Forward     Vault name, counts of notes, files and links", size=SMALL)
    s.text(608, 21, "Search   Inspector", size=SMALL, ha="right")
    s.rect(8, 34, 34, bottom - 26)
    for i, name in enumerate(RIBBON):
        s.rect(12, 42 + 26 * i, 26, 20, name, size=4.3, line=1.6 if name == chosen else 0.7)


def wire_ledger():
    s = Sheet("wire_ledger", 626, 440)
    _chrome(s, 424, "Ledger")
    s.text(56, 52, "Ledger", ha="left", weight="bold", size=10)
    s.text(112, 52, "commits on branches", ha="left", size=SMALL)
    s.rect(394, 42, 70, 18, "Resume", size=7.0)
    s.text(56, 74, "Filter:  All   main   Team", ha="left", size=SMALL)
    for i, (big, words) in enumerate([("N", "rules in force:\nhanded to every program"), ("N", "files changed under\na decision: check again"),
                                      ("N", "lines flagged as\nwritten to steer an AI")]):
        x = 56 + 138 * i
        s.rect(x, 88, 128, 56)
        s.text(x + 8, 102, big, ha="left", weight="bold", size=10)
        s.text(x + 8, 126, words, ha="left", size=6.6)
    s.text(56, 162, "Today", ha="left", weight="bold")
    for i, (kind, words) in enumerate([("DECISION", "Statement lines match a ticket by account reference only."),
                                       ("CORRECTION", "An earlier decision was wrong; this says what is right."),
                                       ("HANDOFF", "Where the last session stopped, for the next program.")]):
        y = 174 + 78 * i
        s.dot(64, y + 10, filled=True)
        s.line([(64, y + 14), (64, y + 74)], lw=0.5)
        s.rect(76, y, 388, 70)
        s.rect(84, y + 6, 62, 14, kind, size=5.8)
        s.text(156, y + 13, "branch · time", ha="left", size=6.4)
        s.text(456, y + 13, "author, in the program", ha="right", size=6.4)
        s.text(84, y + 32, words, ha="left", size=7.2, weight="bold")
        s.text(90, y + 50, "Because: the reason, in full", ha="left", size=6.6)
        s.text(90, y + 62, "Rejected: what was turned down    Still Right  ·  Mark Wrong…", ha="left", size=6.6)
    s.rect(472, 34, 146, 378)
    s.text(480, 48, "WHAT IS KEPT", ha="left", size=6.6, weight="bold")
    s.ax.add_patch(Ellipse((545, 104), 70, 70, facecolor="white", edgecolor=INK, lw=0.8, zorder=3))
    s.ax.add_patch(Ellipse((545, 104), 44, 44, facecolor="white", edgecolor=INK, lw=0.8, zorder=4))
    s.text(545, 104, "N\ncommits", size=6.4)
    s.text(480, 158, "Decision · Correction\nHandoff · Plan    counts", ha="left", size=6.4)
    s.text(480, 198, "WHO KEPT THEM", ha="left", size=6.6, weight="bold")
    s.text(480, 220, "person or program   count\nperson or program   count", ha="left", size=6.4)
    s.text(480, 262, "BRANCHES", ha="left", size=6.6, weight="bold")
    s.text(480, 284, "main  current\nTeam", ha="left", size=6.4)
    s.line([(42, 412), (618, 412)], lw=0.6)
    s.text(610, 419, "rules in force · files · notes · conversations · Ledger commits", ha="right", size=6.2)
    s.save()


def wire_watch():
    s = Sheet("wire_watch", 626, 380)
    _chrome(s, 364, "Ledger")
    s.rect(42, 34, 300, 312)
    s.text(192, 190, "The page the person is on\n(Ledger, a note, a conversation)", size=7.4, style="italic")
    s.rect(350, 34, 268, 312)
    s.text(358, 50, "WATCH", ha="left", weight="bold", size=7.4)
    rows = [("Rules in force", "N decisions handed to every program that connects;\neach with its reason and the program that kept it"),
            ("What burrow_check shows", "the files changed since the last commit and the\ndecisions resting on them: Still Right, Mark Wrong…"),
            ("Written to steer an AI", "lines in the vault that read as instructions to a\nmodel, with their file and line; never handed over")]
    for i, (head, words) in enumerate(rows):
        y = 64 + 98 * i
        s.rect(358, y, 252, 88)
        s.dot(370, y + 14, filled=i == 0)
        s.text(380, y + 14, head, ha="left", weight="bold", size=7.2)
        s.text(366, y + 50, words, ha="left", size=6.4)
    s.text(50, 356, "● status light: green, amber when changed code rests on a decision, red when steering text is found", ha="left", size=6.2)
    s.save()


def wire_programs():
    s = Sheet("wire_programs", 626, 410)
    _chrome(s, 394, "Programs")
    s.text(56, 52, "Programs", ha="left", weight="bold", size=10)
    s.text(56, 70, "The AI programs on this Mac, and whether each will find this vault", ha="left", size=SMALL)
    # Flow map: programs to the vault.
    s.rect(56, 82, 300, 162)
    s.ax.add_patch(Ellipse((300, 157), 46, 46, facecolor="white", edgecolor=INK, lw=0.9, zorder=3))
    s.text(300, 157, "Vault", size=7.2, weight="bold")
    for i, name in enumerate(["Claude Code", "OpenCode", "LM Studio", "Ollama", "llama.cpp"]):
        y = 98 + 28 * i
        s.rect(66, y - 9, 86, 18, name, size=6.6)
        s.line([(152, y), (200, y), (277, 157)], lw=0.6, dashed=i >= 3)
    s.text(206, 236, "solid: connected   dashed: serves a model", size=6.0)
    s.rect(366, 82, 244, 162)
    s.text(374, 96, "Selected program", ha="left", weight="bold", size=7.2)
    s.text(374, 122, "Connected: its settings start Burrow on\nthis vault (file it was read from)", ha="left", size=6.6)
    s.text(374, 158, "Files it read most today\nLast conversation", ha="left", size=6.6)
    s.rect(374, 200, 90, 20, "Connect", size=7)
    s.rect(472, 200, 128, 20, "Copy the setup line", size=7)
    for i, (name, state) in enumerate([("Claude Code", "Connected"), ("OpenCode", "Not set up"), ("LM Studio", "Another vault"), ("Ollama", "Server running")]):
        y = 258 + 30 * i
        s.rect(56, y, 554, 26)
        s.text(66, y + 13, name, ha="left", size=7.2, weight="bold")
        s.rect(250, y + 5, 90, 16, state, size=6.4)
        s.text(600, y + 13, "Connect   ·   copy line", ha="right", size=6.4)
    s.save()


# ---------------------------------------------------------------- added 15 November 2026

def activity_answer():
    """The knowledge path: how a question about the person's material is answered from the vault."""
    s = Sheet("activity_answer", 626, 760)
    s.rect(4, 6, 618, 748, z=1)
    s.line([(170, 6), (170, 754)])
    s.line([(470, 6), (470, 754)])
    s.line([(4, 28), (622, 28)])
    for x, words in [(87, "Person or AI program"), (320, "Burrow engine"), (546, "Ollama, on this Mac")]:
        s.text(x, 17, words, weight="bold", size=8.2)
    A, B, C = 87, 320, 546
    s.start(A, 46)
    act(s, A, 92, "Ask a question about\nthe person's material", w=150)
    s.line([(A, 53), (A, 73)], "fill")
    act(s, B, 92, "Decide: does the question\nneed the vault?", w=200)
    s.line([(A + 75, 92), (B - 100, 92)], "fill")
    s.diamond(B, 146)
    s.line([(B, 111), (B, 131)], "fill")
    s.text(B + 20, 138, "[no: reasoning or general]", size=SMALL, ha="left")
    s.text(B - 8, 172, "[yes]", size=SMALL, ha="right")
    # No vault: straight to the model.
    s.line([(B + 15, 146), (612, 146), (612, 470), (601, 470)], "fill")
    act(s, C, 206, "Embed the\nquestion", w=110)
    act(s, B, 206, "Rank pieces by words and\nby meaning; merge the two", w=200)
    s.line([(B, 161), (B, 187)], "fill")
    s.line([(C - 55, 206), (B + 100, 206)], "fill", dashed=True)
    s.text(C - 61, 196, "vector", size=SMALL, ha="right")
    s.diamond(B, 262)
    s.line([(B, 225), (B, 247)], "fill")
    s.text(B + 20, 254, "[closest files are code]", size=SMALL, ha="left")
    act(s, B + 50, 312, "Follow links one step", w=150, h=30)
    s.line([(B + 15, 262), (B + 50, 262), (B + 50, 297)], "fill")
    s.line([(B - 15, 262), (B - 110, 262), (B - 110, 352), (B - 100, 352)], "fill")
    s.text(B - 104, 280, "[notes and\ndocuments]", size=SMALL, ha="left")
    act(s, B, 352, "Add the decisions that fit,\nwith their reasons", w=200)
    s.line([(B + 50, 327), (B + 50, 333)], "fill")
    act(s, B, 410, "Fit the excerpts to the model's\nmeasured budget, with file:line", w=210)
    s.line([(B, 371), (B, 391)], "fill")
    act(s, C, 470, "Answer from the\nexcerpts, citing\nfile:line", w=110, h=50)
    s.line([(B + 105, 410), (C, 410), (C, 445)], "fill")
    s.text(606, 300, "[no]", size=SMALL, ha="right")
    act(s, B, 540, "Check every cited file:line\nagainst what was shown", w=200)
    s.line([(C, 495), (C, 540), (B + 100, 540)], "fill")
    s.diamond(B, 600)
    s.line([(B, 559), (B, 585)], "fill")
    s.text(B + 20, 592, "[a place not shown]", size=SMALL, ha="left")
    s.text(B - 20, 592, "[all shown]", size=SMALL, ha="right")
    act(s, B + 50, 660, "Ask once more with a correction;\nkeep the better-grounded answer", w=184, h=40)
    s.line([(B + 15, 600), (B + 50, 600), (B + 50, 640)], "fill")
    act(s, A, 660, "Read the answer, its\nsources and the decision\nline: what was read, why", w=150, h=50)
    s.line([(B - 15, 600), (A, 600), (A, 635)], "fill")
    s.line([(B - 42, 660), (A + 75, 660)], "fill")
    s.stop(A, 728)
    s.line([(A, 685), (A, 719)], "fill")
    s.save()


def states_decision():
    """The life of a decision in the Ledger."""
    s = Sheet("states_decision", 626, 420)
    s.start(20, 72)
    s.diamond(90, 72)
    s.line([(27, 72), (75, 72)], "fill")
    s.text(48, 58, "kept with\na reason", size=6.6)
    # In force.
    s.rounded(280, 44, 140, 56, "In force\nhanded to every program", radius=9, size=7.4)
    s.line([(105, 72), (280, 72)], "fill")
    s.text(190, 64, "[no overlap]", size=6.6)
    # Overlap.
    s.rounded(30, 150, 150, 50, "Refused once\nthe overlapping decision\nshown with its reason", radius=9, size=7.0)
    s.line([(90, 87), (90, 150)], "fill")
    s.text(96, 118, "[overlaps one\nin force]", size=6.4, ha="left")
    s.line([(180, 160), (226, 160), (226, 84), (280, 84)], "fill")
    s.text(220, 126, "supersedes,\nor alongside", size=6.4, ha="right")
    s.rounded(30, 262, 150, 50, "Unresolved\nboth shown to programs\nand to the person", radius=9, size=7.0)
    s.line([(105, 200), (105, 262)], "fill")
    s.text(111, 231, "[kept again without\nsaying which holds]", size=6.4, ha="left")
    s.line([(180, 274), (262, 274), (262, 96), (280, 96)], "fill")
    s.text(186, 254, "person: Keep\nnewer or both", size=6.4, ha="left")
    # Check again.
    s.rounded(280, 262, 140, 56, "Check again\na file it rests on\nhas changed", radius=9, size=7.2)
    s.line([(334, 100), (334, 262)], "fill")
    s.text(340, 150, "[a file it\nrests on\nchanges]", size=6.4, ha="left")
    s.line([(396, 262), (396, 100)], "fill")
    s.text(402, 214, "Still Right:\na confirmation\nis kept", size=6.4, ha="left")
    # Retired.
    s.rounded(480, 18, 112, 48, "Replaced\nby a newer decision", radius=9, size=7.0)
    s.rounded(480, 140, 112, 48, "Marked wrong\nby a correction", radius=9, size=7.0)
    s.line([(420, 60), (480, 46)], "fill")
    s.text(448, 38, "superseded", size=6.4)
    s.line([(420, 90), (480, 158)], "fill")
    s.text(470, 106, "Mark Wrong", size=6.4, ha="right", back=True)
    s.line([(420, 290), (536, 290), (536, 188)], "fill")
    s.text(478, 282, "Mark Wrong", size=6.4)
    s.stop(612, 42)
    s.line([(592, 42), (603, 42)], "fill")
    s.stop(612, 164)
    s.line([(592, 164), (603, 164)], "fill")
    s.note(18, 344, 300, 56, "No commit is ever changed or deleted. Replaced and\nMarked wrong are later commits that retire the decision,\nso the history stays readable and a program is told why.", size=6.6)
    s.save()


def sequence_handover():
    """Work carried from a cloud model in one program to a local model in another."""
    s = Sheet("sequence_handover", 626, 640)
    P, CC, B, L, OC = 50, 166, 318, 450, 574
    _lifelines(s, [(P, ":Person"), (CC, ":Claude Code\n(cloud model)"), (B, ":burrow\nMCP and hooks"), (L, ":Ledger and\nfolds"),
                   (OC, ":OpenCode\n(Gemma, local)")], 630, half=44)
    for x, a, b in [(CC, 58, 250), (B, 76, 110), (L, 90, 106), (B, 160, 190), (B, 214, 244), (L, 228, 242), (OC, 300, 600),
                    (B, 318, 344), (B, 368, 420), (L, 382, 404), (B, 498, 530)]:
        s.rect(x - 4, a, 8, b - a, z=4)
    _message(s, P, CC - 4, 62, "\"handle unmatched payments\"")
    _message(s, CC + 4, B - 4, 80, "burrow_commit(decision, because, rejected)")
    _message(s, B + 4, L - 4, 94, "commit")
    _message(s, B - 4, CC + 4, 108, "kept as <id>", True)
    _self(s, CC, 122, "work on; the context fills", drop=16)
    _message(s, CC + 4, B - 4, 164, "PreCompact hook")
    _self(s, B, 170, "fold: requests, reasons,\nerrors, word for word", drop=18)
    _message(s, CC + 4, B - 4, 218, "SessionEnd hook")
    _message(s, B + 4, L - 4, 232, "handoff: where it stopped")
    _message(s, P, OC - 4, 290, "\"carry on where Claude stopped\"")
    _message(s, OC - 4, B + 4, 322, "first tool call")
    _message(s, B + 4, OC - 4, 342, "result, with the decisions in force, once", True)
    _message(s, OC - 4, B + 4, 372, "burrow_resume")
    _message(s, B + 4, L - 4, 386, "plan, handoff, fold")
    _message(s, L - 4, B + 4, 402, "", True)
    _message(s, B + 4, OC - 4, 418, "where it stopped, the error, the constraint", True)
    s.line([(OC - 4, 440), (OC - 30, 440), (OC - 30, 470), (OC - 4, 470)], "fill")
    s.text(OC - 36, 455, "continue the right step,\nkeeping the decision", ha="right", size=7.2, back=True)
    _message(s, OC - 4, B + 4, 502, "burrow_check")
    _message(s, B + 4, OC - 4, 528, "verdict per decision", True)
    _message(s, OC - 4, P, 590, "done, with the decision kept", True)
    s.save()


def _lollipop(s, x, y, words, left=True):
    from matplotlib.patches import Circle
    s.ax.add_patch(Circle((x, y), 5, facecolor="white", edgecolor=INK, lw=0.8, zorder=5))
    s.text(x + (-8 if left else 8), y - 11, words, size=6.4, ha="right" if left else "left")


def components():
    """UML component view of the Swift package and what plugs into it."""
    from matplotlib.patches import Arc
    s = Sheet("components", 626, 470)

    def comp(x, y, w, h, name, note=""):
        component(s, x, y, w, h, f"«component»\n{name}" + (f"\n{note}" if note else ""))

    def socket(x, y):
        s.ax.add_patch(Arc((x, y), 14, 14, theta1=90, theta2=270, edgecolor=INK, lw=0.8, zorder=5))

    # Outside programs.
    s.rect(8, 10, 176, 40, "AI programs\n(Claude Code, OpenCode, n8n…)", size=6.8)
    s.rect(224, 10, 176, 40, "Hooks and plugins\n(Stop, PreCompact, pre-commit,\nOpenCode, OpenClaw, Hermes)", size=6.4)
    s.rect(440, 10, 178, 40, "The person", size=7.2)
    # Front ends.
    comp(8, 104, 176, 60, "BurrowMCP", "MCP server, stdio")
    comp(224, 104, 176, 60, "burrow", "command line, chat, TUI")
    comp(440, 104, 178, 60, "Burrow.app", "desktop application")
    s.line([(96, 50), (96, 80)]); socket(96, 84); _lollipop(s, 96, 92, "MCP tools (JSON-RPC)", left=False)
    s.line([(96, 97), (96, 104)])
    s.line([(312, 50), (312, 80)]); socket(312, 84); _lollipop(s, 312, 92, "burrow check, connect", left=False)
    s.line([(312, 97), (312, 104)])
    s.line([(529, 50), (529, 104)], "open", dashed=True); s.text(535, 76, "uses", size=6.4, ha="left")
    # Engine.
    comp(70, 214, 486, 74, "BurrowTools", "VaultTools · Ledger · AskLedger · sessions and folds · check and verdicts · guards · teams")
    for x in (96, 312, 529):
        s.line([(x, 164), (x, 214)], "open", dashed=True)
    s.text(316, 190, "«use» VaultTools", size=6.4, ha="left")
    comp(70, 330, 486, 70, "BurrowCore", "vault and index · retrieval · engine · citations · link approvals · bridges · Ollama client")
    s.line([(313, 288), (313, 330)], "open", dashed=True); s.text(319, 309, "«use» Vault", size=6.4, ha="left")
    # Stores and the local model service.
    s.rect(70, 428, 220, 34, "Files: vault, .burrow (index, Ledger, sessions),\nBurrow's own folder, team folder", size=6.4)
    s.rect(336, 428, 220, 34, "Ollama at 127.0.0.1\n(embeddings; local answers)", size=6.6)
    s.line([(180, 400), (180, 428)], "open", dashed=True)
    s.line([(446, 400), (446, 428)], "open", dashed=True)
    s.text(452, 414, "HTTP, loopback", size=6.2, ha="left")
    s.save()


def wire_ask():
    s = Sheet("wire_ask", 626, 420)
    _chrome(s, 404, "All")
    s.rect(42, 34, 400, 22)
    s.text(52, 45, "Graph     Ask ×     +", ha="left", size=6.8)
    s.text(56, 76, "The question, as the person asked it", ha="left", weight="bold", size=8.4)
    s.text(56, 104, "The answer, in the model's words, with each claim followed by its place:\n(Law/act-part-02.md:71)  and a decision used, by its label:  [Ledger 2026…-a355]", ha="left", size=6.8)
    s.rect(52, 128, 380, 22)
    s.text(60, 139, "⚙  Decision line: read the vault or not, which files led, the method used", ha="left", size=6.6)
    s.rect(52, 158, 380, 22, dashed=True)
    s.text(60, 169, "⚠  Shown only if a cited place was not among what the model read", ha="left", size=6.6)
    s.text(56, 196, "Used", ha="left", weight="bold", size=7.2)
    for i in range(5):
        y = 212 + 18 * i
        s.dot(62, y)
        s.text(72, y, "file read, in the order it was used          note · code · Ledger", ha="left", size=6.6)
    s.text(56, 318, "Seconds taken, on this Mac      Keep as Note      What Should Burrow Remember?", ha="left", size=6.6)
    s.rect(42, 336, 400, 54)
    s.text(52, 352, "Ask about this vault…", ha="left", size=7.0, style="italic")
    s.text(432, 378, "model ▾   Ask", ha="right", size=6.6)
    s.rect(450, 34, 168, 238)
    s.text(534, 150, "Map of the vault:\nthe files read light up", size=6.8, style="italic")
    s.rect(450, 280, 168, 30)
    s.text(534, 295, "▮▮▮▮▮  Read N notes and files", size=6.6)
    s.save()


def screen_flow():
    """A person's first hour with Burrow, from install to a decision reviewed."""
    s = Sheet("screen_flow", 626, 430)
    boxes = [(8, 20, "Install\none command, or\nthe app from Releases"), (164, 20, "Open a vault\nchoose a folder of\nMarkdown notes"),
             (320, 20, "Index builds\nprogress; words first,\nmeaning when ready"), (476, 20, "Link a code folder\nread-only"),
             (476, 150, "Approve the folder\nonly the person,\non this Mac"), (320, 150, "Programs page\nConnect Claude Code,\nOpenCode, n8n…"),
             (164, 150, "Work in the AI program\ndecisions kept with\nreasons; changes checked"), (8, 150, "Ledger and Watch\nStill Right, Mark Wrong,\nKeep newer or both"),
             (8, 290, "Ask the vault\nanswers with sources"), (164, 290, "Share with a team\nheld until the\nperson approves")]
    w, h = 142, 64
    for x, y, words in boxes:
        s.rounded(x, y, w, h, words, radius=8, size=6.9)
    for a, b in [((150, 52), (164, 52)), ((306, 52), (320, 52)), ((462, 52), (476, 52)), ((547, 84), (547, 150)),
                 ((476, 182), (462, 182)), ((320, 182), (306, 182)), ((164, 182), (150, 182))]:
        s.line([a, b], "fill")
    s.line([(79, 214), (79, 290)], "fill")
    s.line([(150, 214), (235, 290)], "fill")
    s.text(200, 246, "a decision\nto share", size=6.4, ha="left")
    # Alternative paths.
    s.note(320, 290, 140, 52, "Ollama not running:\nsearch goes on by words;\nthe app says so", size=6.4)
    s.line([(391, 84), (391, 110), (469, 110), (469, 300), (460, 300)], dashed=True, lw=0.6)
    s.note(476, 290, 142, 52, "Folder not approved:\nnothing in it is read,\nand the vault says why", size=6.4)
    s.line([(547, 214), (547, 290)], dashed=True, lw=0.6)
    s.note(8, 380, 290, 40, "A change that breaks a decision is held in the AI program\nuntil it is undone or the person overrides it.", size=6.4)
    s.save()


ALL = (use_cases, sequence_session, activity_check, classes, architecture, schema, deployment, wire_ledger, wire_watch, wire_programs,
       activity_answer, states_decision, sequence_handover, components, wire_ask, screen_flow)

if __name__ == "__main__":
    wanted = set(sys.argv[1:])
    for draw in ALL:
        if not wanted or draw.__name__ in wanted:
            draw()
