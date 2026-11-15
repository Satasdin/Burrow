// An interactive, scripted Burrow window. Every question, answer, file name and decision below was taken from the
// real app (its screenshots in docs/report/figures); nothing is generated here. Nothing is sent anywhere.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (sel, el = root) => el.querySelector(sel);
  const make = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  // ---------------------------------------------------------------- the vault graph (canvas)
  const CLUSTERS = {
    law:      {label: "LAW",      cx: .34, cy: .26, r: .17, n: 30, color: [232, 138, 160]},
    project:  {label: "PROJECT",  cx: .66, cy: .50, r: .15, n: 46, color: [150, 190, 255]},
    software: {label: "SOFTWARE", cx: .30, cy: .66, r: .17, n: 30, color: [110, 220, 180]},
    skills:   {label: "SKILLS",   cx: .58, cy: .84, r: .10, n: 12, color: [176, 150, 255]},
  };
  let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const nodes = [], edges = [];
  for (const [key, c] of Object.entries(CLUSTERS)) {
    const start = nodes.length;
    for (let i = 0; i < c.n; i++) {
      const a = rnd() * Math.PI * 2, d = Math.sqrt(rnd()) * c.r * (key === "project" ? .8 : 1);
      nodes.push({key, x: c.cx + Math.cos(a) * d * 1.15, y: c.cy + Math.sin(a) * d, s: key === "project" ? 1.6 + rnd() * 1.6 : 1.2 + rnd() * 1.2, lit: 0, target: 0, label: ""});
    }
    for (let i = start; i < nodes.length; i++) { if (key !== "project" && rnd() < .14) continue; const j = start + Math.floor(rnd() * c.n); if (j !== i) edges.push([i, j]); }
  }
  for (let i = 0; i < 26; i++) edges.push([Math.floor(rnd() * nodes.length), Math.floor(rnd() * nodes.length)]);
  edges.forEach(([a, b]) => { if (a !== b) { nodes[a].deg = (nodes[a].deg || 0) + 1; nodes[b].deg = (nodes[b].deg || 0) + 1; } });
  const pick = (key, labels) => {
    // spread the lit files down the cluster so their labels never sit on one another
    const pool = nodes.filter((n) => n.key === key).sort((a, b) => a.y - b.y);
    return labels.map((label, i) => ({n: pool[Math.floor((i + .5) * pool.length / labels.length)], label}));
  };
  const LIT = {
    law: pick("law", ["act-part-02-office-of-the-data-commissioner", "complaints-regs-part-01-02-lodging-and-handling", "act-part-01-preliminary",
                      "general-regs-part-01-02-rights-of-a-data-subject", "registration-regs-regulations-01-18", "general-regs-part-07-transfer-outside-kenya"]),
    code: [...pick("project", ["DECISIONS", "Markdown.swift", "Views.swift", "VaultTools.swift", "Retrieval.swift"]), ...pick("software", ["sqlite-releases-2026-01-to-07-3.5…"])],
    none: [],
  };
  let filter = {notes: true, code: true, loose: true}, litSet = [], lines = 0, lineTarget = 0;

  function graph(canvas, opts = {}) {
    const ctx = canvas.getContext("2d");
    let w = 0, h = 0, hover = null;
    const size = () => {
      const r = canvas.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
      w = r.width; h = r.height; canvas.width = w * dpr; canvas.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    new ResizeObserver(size).observe(canvas); size();
    if (opts.hover) {
      canvas.addEventListener("mousemove", (e) => {
        const r = canvas.getBoundingClientRect(), x = (e.clientX - r.left) / w, y = (e.clientY - r.top) / h;
        hover = null;
        for (const [k, c] of Object.entries(CLUSTERS)) if (Math.hypot(x - c.cx, y - c.cy) < c.r * 1.1) hover = k;
      });
      canvas.addEventListener("mouseleave", () => { hover = null; });
    }
    const visible = (n) => (n.key === "project" ? filter.code : filter.notes) && (filter.loose || n.deg > 0);
    return () => {
      ctx.clearRect(0, 0, w, h);
      ctx.lineWidth = .6;
      for (const [a, b] of edges) {
        const A = nodes[a], B = nodes[b]; if (!visible(A) || !visible(B)) continue;
        ctx.strokeStyle = "rgba(200,200,200,.10)"; ctx.beginPath(); ctx.moveTo(A.x * w, A.y * h); ctx.lineTo(B.x * w, B.y * h); ctx.stroke();
      }
      for (const n of nodes) {
        n.lit += (n.target - n.lit) * .08;
        if (!visible(n)) continue;
        const [r, g, b] = CLUSTERS[n.key].color, dim = hover && hover !== n.key ? .35 : 1;
        ctx.fillStyle = `rgba(${r},${g},${b},${(.55 + .3 * (n.key === "project")) * dim})`;
        if (opts.hover) { ctx.shadowColor = `rgba(${r},${g},${b},.9)`; ctx.shadowBlur = 8; }
        ctx.beginPath(); ctx.arc(n.x * w, n.y * h, n.s, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
        if (n.lit > .02) {
          const glow = ctx.createRadialGradient(n.x * w, n.y * h, 0, n.x * w, n.y * h, 16 * n.lit);
          glow.addColorStop(0, `rgba(255,236,170,${.85 * n.lit})`); glow.addColorStop(1, "rgba(255,214,133,0)");
          ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(n.x * w, n.y * h, 16 * n.lit, 0, 7); ctx.fill();
          ctx.fillStyle = `rgba(255,246,214,${n.lit})`; ctx.beginPath(); ctx.arc(n.x * w, n.y * h, 3.4, 0, 7); ctx.fill();
        }
      }
      if (opts.lines) {
        lines += (lineTarget - lines) * .06;
        // the path the model took through what it read, in the order it read it
        ctx.lineWidth = 1.4;
        for (let k = 1; k < litSet.length; k++) {
          const A = litSet[k - 1].n, B = litSet[k].n, a = Math.min(A.lit, B.lit);
          if (a < .05) continue;
          ctx.strokeStyle = `rgba(255,232,170,${.7 * a * lines})`;
          ctx.beginPath(); ctx.moveTo(A.x * w, A.y * h); ctx.lineTo(B.x * w, B.y * h); ctx.stroke();
        }
      }
      ctx.font = "600 10.5px -apple-system, system-ui, sans-serif"; ctx.textAlign = "center"; if ("letterSpacing" in ctx) ctx.letterSpacing = "2px";
      for (const [k, c] of Object.entries(CLUSTERS)) {
        ctx.fillStyle = hover === k ? "rgba(255,255,255,.9)" : `rgba(${c.color.join(",")},${opts.lines && litSet.length ? .3 : .62})`;
        ctx.fillText(c.label, c.cx * w, (c.cy - c.r - .04) * h);
      }
      if ("letterSpacing" in ctx) ctx.letterSpacing = "0px";
      ctx.textAlign = "left"; ctx.font = "600 11px -apple-system, system-ui, sans-serif";
      for (const {n, label} of litSet) if (n.lit > .5 && w > 400) { ctx.fillStyle = `rgba(240,240,240,${n.lit})`; const max = w > 420 ? 30 : 18; ctx.fillText(label.length > max ? label.slice(0, max - 1) + "…" : label, n.x * w + 8, n.y * h + 4); }
    };
  }
  const draws = [];
  root.querySelectorAll("canvas[data-graph]").forEach((c) => draws.push(graph(c, {hover: c.dataset.graph === "map", lines: c.dataset.graph === "ask"})));
  let on = true;
  const loop = () => { if (on) draws.forEach((d) => d()); requestAnimationFrame(loop); };
  new IntersectionObserver((e) => { on = e[0].isIntersecting; }).observe(root);
  requestAnimationFrame(loop);
  const light = (set) => { nodes.forEach((n) => n.target = 0); litSet = set; lineTarget = set.length ? 1 : 0; set.forEach(({n}, i) => setTimeout(() => n.target = 1, still ? 0 : 140 * i)); };

  // the files read light up in the file tree too
  const tree = (used) => root.querySelectorAll(".demo-tree [data-f]").forEach((li) => li.classList.toggle("lit", used.includes(li.dataset.f)));

  // ---------------------------------------------------------------- views
  const views = root.querySelectorAll("[data-view]");
  const tabs = root.querySelectorAll("[data-show]");
  function show(name) {
    views.forEach((v) => v.hidden = v.dataset.view !== name);
    tabs.forEach((t) => t.setAttribute("aria-selected", String(t.dataset.show === name)));
    $(".demo-tab").textContent = name[0].toUpperCase() + name.slice(1);
    if (name !== "ask") { light([]); tree([]); }
  }
  tabs.forEach((t) => t.addEventListener("click", () => { touched = true; show(t.dataset.show); }));

  // ---------------------------------------------------------------- Ask
  const QUESTIONS = [
    {q: "Under Kenya's Data Protection Act, 2019, how long is the Data Commissioner's term of office, and can it be renewed?", lit: "law",
     answer: [{t: "The Data Commissioner shall be appointed for a single term of six years and shall not be eligible for a re-appointment. "}, {cite: "Law/act-part-02-office-of-the-data-commissioner.md:71"}],
     line: "Read the vault: the closest files are notes and documents. Method: Answer from documents.",
     used: ["act-part-02-office-of-the-data-commissioner", "complaints-regs-part-01-02-lodging-and-handling", "act-part-01-preliminary", "general-regs-part-01-02-rights-of-a-data-subject", "registration-regs-regulations-01-18", "general-regs-part-07-transfer-outside-kenya"],
     time: "15.0 s, on this Mac"},
    {q: "How does Burrow merge the word ranking and the meaning ranking?", lit: "code",
     answer: [{t: "Burrow merges the word and meaning rankings using Reciprocal Rank Fusion. The method is defined in "}, {code: "Project/Sources/BurrowCore/Retrieval.swift"}, {t: " at line 118. Each ID's score is incremented by "}, {code: "1.0 / Double(60 + rank + 1)"}, {t: ", a weight is applied by the file path of the chunk, and the IDs are sorted by score into one ranking. "}, {cite: "Project/Sources/BurrowCore/Retrieval.swift:123"}],
     line: "Read 10 notes and files: the closest files are code, so Burrow followed their links.",
     used: ["DECISIONS", "Markdown.swift", "Views.swift", "VaultTools.swift", "Retrieval.swift", "sqlite-releases-2026-01-to-07-3.5…"], read: "Read 10 notes and files", time: ""},
    {q: "A shop sells pens at 15 shillings each. Amina buys 8 pens and pays with a 200 shilling note. How much change does she get?", lit: "none",
     answer: [{t: "Total cost = 8 pens × 15 shillings = 120 shillings. Change = 200 − 120 = 80. Check: 120 + 80 = 200. Answer: 80"}],
     line: "Answered without the vault: this is a task to work out, not something to look up. Method: Work a calculation.",
     used: [], time: "4.4 s, on this Mac"},
  ];
  const chips = $(".demo-chips"), out = $(".demo-answer"), input = $(".demo-input input"), status = $(".demo-status");
  const strip = $(".demo-strip"), marks = $(".demo-strip .marks"), stripText = $(".demo-strip span"), idle = stripText.textContent;
  const FOLDER = {law: "#f08da0", code: "#7fb0ff"};
  const reading = (item) => {
    marks.replaceChildren(); stripText.textContent = idle;
    if (!item || !item.used.length) return;
    item.used.forEach((u, k) => { const m = make("i"); m.style.setProperty("--c", /^sqlite/.test(u) ? "#6fe0c0" : FOLDER[item.lit]); m.style.animationDelay = (still ? 0 : 140 * k) + "ms"; marks.appendChild(m); });
    stripText.textContent = item.read || `Read ${item.used.length} notes and files`;
  };
  QUESTIONS.forEach((item, i) => {
    const b = make("button", "demo-chip", item.q); b.title = item.q;
    b.type = "button"; b.addEventListener("click", () => { touched = true; ask(i); }); chips.appendChild(b);
  });
  let run = 0;
  const wait = (ms) => new Promise((r) => setTimeout(r, still ? 0 : ms));
  async function ask(i) {
    const id = ++run, item = QUESTIONS[i];
    show("ask"); out.replaceChildren(); light([]); tree([]); reading(null);
    chips.querySelectorAll("button").forEach((b, j) => b.setAttribute("aria-pressed", String(j === i)));
    input.value = "";
    for (let k = 1; k <= item.q.length; k += still ? item.q.length : 2) { if (id !== run) return; input.value = item.q.slice(0, k); await wait(14); }
    const h = make("h4", "demo-q", item.q); out.appendChild(h);
    status.hidden = false; status.querySelector("span").textContent = item.lit === "none" ? "Deciding whether the vault is needed…" : "Reading the vault…";
    await wait(500); if (id !== run) return;
    light(LIT[item.lit]); tree(item.used); reading(item); await wait(item.lit === "none" ? 300 : 900); if (id !== run) return;
    status.hidden = true;
    const p = make("p", "demo-text"); out.appendChild(p);
    for (const part of item.answer) {
      if (part.cite) { p.appendChild(make("span", "demo-cite", "(" + part.cite + ")")); continue; }
      if (part.code) { p.appendChild(make("code", "", part.code)); continue; }
      const span = make("span"); p.appendChild(span);
      const words = part.t.split(/(\s+)/);
      for (let k = 0; k < words.length; k++) { if (id !== run) return; span.textContent += words[k]; if (k % 2 === 0) await wait(22); }
    }
    out.appendChild(make("p", "demo-line", item.line));
    if (item.used.length) {
      out.appendChild(make("div", "demo-used-h", "Used"));
      const ul = make("ul", "demo-used"); item.used.forEach((u) => { const li = make("li"); li.append(make("i"), make("span", "", u), make("em", "", /\.\w+$/.test(u) ? "code" : "note")); ul.appendChild(li); }); out.appendChild(ul);
    }
    const foot = make("p", "demo-foot"); [item.time, "Keep as Note", "What Should Burrow Remember?"].filter(Boolean).forEach((t) => foot.appendChild(make("span", "", t))); out.appendChild(foot);
  }
  $(".demo-input").addEventListener("submit", (e) => {
    e.preventDefault(); touched = true;
    const text = input.value.trim().toLowerCase(); if (!text) return;
    const hit = QUESTIONS.findIndex((q) => q.q.toLowerCase().startsWith(text.slice(0, 18)));
    if (hit >= 0) { ask(hit); return; }
    out.replaceChildren(make("h4", "demo-q", input.value), make("p", "demo-line", "This demo answers the three questions above, with the real answers from the app. Download Burrow to ask your own vault: it runs on your Mac."));
    light([]); reading(null);
  });

  // ---------------------------------------------------------------- Ledger
  const DECISIONS = [
    {branch: "Team", time: "23:24", av: "WK", who: "Wanjiru Kamau in the terminal", text: "Launch day support runs from the Nairobi office, 6am to 10pm.", because: "Two of the three of us are in Nairobi and the first routes are Thika Road."},
    {branch: "Synced", time: "23:24", av: "WK", who: "Wanjiru Kamau in the terminal", text: "Refund pending items are settled within two working days.", because: "Finance closes the M-Pesa statement weekly."},
    {branch: "Synced", time: "23:24", av: "OO", who: "Otieno Ouma in the terminal", text: "The support phone line is answered in English and Swahili.", because: "Most passengers on Thika Road call in Swahili."},
    {branch: "main", av: "CC", who: "claude-opus-5-5 · claude-code", text: "reconcile_statement matches a statement line to a ticket by its account reference and nothing else.",
     because: "Finance meeting, 3 June: until April a fallback matched an unknown reference to the open ticket with the same phone and amount. Conductors often pay from their own phone for a whole group, so on Easter Monday 31 tickets on route 46 were marked paid against the wrong passengers.",
     rejected: "Matching on phone number and amount: phone and fare repeat when a conductor pays for a group, causing the Easter Monday mispayments."},
  ];
  const list = $(".demo-ledger-list"); let branch = "All";
  function renderLedger() {
    list.replaceChildren();
    DECISIONS.filter((d) => branch === "All" || d.branch === branch).forEach((d) => {
      const card = make("article", "demo-card");
      const top = make("div", "demo-card-top");
      const who = make("span", "demo-who"); who.append(make("span", "demo-av " + d.av.toLowerCase(), d.av), d.who);
      top.append(make("span", "demo-kind", d.wrong ? "MARKED WRONG" : "DECISION"), make("span", "demo-meta", [d.branch, d.time].filter(Boolean).join("  ")), who);
      card.append(top, make("p", "demo-card-text", d.text));
      const bc = make("div", "demo-because"); bc.append(make("b", "", "Because"), make("span", "", d.because)); card.appendChild(bc);
      if (d.rejected) { const rj = make("div", "demo-rejected"); rj.append(make("b", "", "Turned down"), make("span", "", d.rejected)); card.appendChild(rj); }
      const act = make("div", "demo-actions");
      const right = make("button", "", d.confirmed ? "Still right ✓" : "Still Right"); right.type = "button";
      const wrong = make("button", "", d.wrong ? "Undo" : "Mark Wrong…"); wrong.type = "button";
      right.addEventListener("click", () => { d.confirmed = !d.confirmed; d.wrong = false; renderLedger(); });
      wrong.addEventListener("click", () => { d.wrong = !d.wrong; d.confirmed = false; renderLedger(); });
      act.append(right, wrong); card.appendChild(act);
      if (d.wrong) card.classList.add("wrong");
      list.appendChild(card);
    });
    root.querySelectorAll(".demo-rules").forEach((e) => e.textContent = 6 - DECISIONS.filter((d) => d.wrong).length);
  }
  root.querySelectorAll("[data-branch]").forEach((b) => b.addEventListener("click", () => {
    branch = b.dataset.branch; root.querySelectorAll("[data-branch]").forEach((x) => x.setAttribute("aria-pressed", String(x === b))); renderLedger();
  }));
  renderLedger();

  // ---------------------------------------------------------------- Programs
  const PROGRAMS = [
    {name: "Claude Code", id: "claude-code", state: "Not set up"},
    {name: "OpenCode", id: null, state: "Set up in a project", on: true},
    {name: "LM Studio", id: null, state: "Not set up"},
    {name: "llama.cpp", id: null, state: "Not set up"},
    {name: "Ollama", id: null, state: "Server running", server: true},
  ];
  const plist = $(".demo-programs"), cmd = $(".demo-connect code");
  function renderPrograms() {
    plist.replaceChildren();
    PROGRAMS.forEach((p) => {
      const row = make("div", "demo-prog" + (p.on ? " on" : "") + (p.server ? " server" : ""));
      const dot = make("i"); const txt = make("div"); txt.append(make("b", "", p.name), make("span", "", p.state));
      row.append(dot, txt);
      if (p.id && !p.on) { const b = make("button", "", "Connect"); b.type = "button"; b.addEventListener("click", () => { p.on = true; p.state = "Connected (demo)"; cmd.textContent = `burrow connect ${p.id} ~/Notes --write`; $(".demo-progcount").textContent = "2 set up for this vault · 1 active in the last 30 minutes"; renderPrograms(); }); row.appendChild(b); }
      plist.appendChild(row);
    });
    $(".demo-flow").replaceChildren(...PROGRAMS.map((p, i) => { const l = make("span", "demo-flowline" + (p.on ? " on" : "") + (p.server ? " server" : "")); l.style.setProperty("--i", i); return l; }));
  }
  renderPrograms();

  // ---------------------------------------------------------------- Map filters
  root.querySelectorAll("[data-filter]").forEach((c) => c.addEventListener("change", () => { filter[c.dataset.filter] = c.checked; }));

  // ---------------------------------------------------------------- play once when first seen
  let touched = false;
  show("ask");
  new IntersectionObserver((e, obs) => {
    if (e[0].isIntersecting) { obs.disconnect(); setTimeout(() => { if (!touched) ask(0); }, still ? 0 : 700); }
  }, {threshold: .4}).observe(root);
})();
