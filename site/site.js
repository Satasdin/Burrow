// Copy buttons, the install tabs, and clips that play only while on screen.
(() => {
  const check = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><path d="m3.5 8.5 3 3 6-7"/></svg>';
  document.querySelectorAll("[data-copy]").forEach((button) => {
    const icon = button.innerHTML;
    button.addEventListener("click", async () => {
      const text = button.parentElement.querySelector("code").textContent;
      try { await navigator.clipboard.writeText(text); } catch { return; }
      button.innerHTML = check;
      button.setAttribute("aria-label", "Copied");
      setTimeout(() => { button.innerHTML = icon; button.setAttribute("aria-label", "Copy"); }, 1600);
    });
  });

  const tabs = document.querySelectorAll(".tabs button");
  tabs.forEach((tab) => tab.addEventListener("click", () => {
    tabs.forEach((t) => t.setAttribute("aria-selected", String(t === tab)));
    document.getElementById("installcmd").textContent = tab.dataset.cmd;
  }));

  // A download from another site gives the page no sign it started, and Safari first asks whether to allow downloads
  // from this site; a tester saw nothing happen (16 November). So the page says what should happen and what to do if not.
  const dmg = document.getElementById("getdmg"), started = document.getElementById("started");
  if (dmg && started) dmg.addEventListener("click", () => { started.hidden = false; });

  const menu = document.querySelector(".menu"), sheet = document.getElementById("sitemenu");
  if (menu && sheet) {
    const set = (open) => { menu.setAttribute("aria-expanded", String(open)); sheet.hidden = !open; };
    menu.addEventListener("click", () => set(sheet.hidden));
    addEventListener("keydown", (e) => { if (e.key === "Escape" && !sheet.hidden) { set(false); menu.focus(); } });
    matchMedia("(min-width: 861px)").addEventListener("change", (e) => { if (e.matches) set(false); });
  }

  const head = document.querySelector("header");
  const mark = () => head && head.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", mark, {passive: true}); mark();

  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const hero = document.querySelector(".stage video");
  if (hero && still) { hero.removeAttribute("autoplay"); hero.pause(); hero.controls = true; }

  const loops = document.querySelectorAll("video[loop]");
  if (still) { loops.forEach((v) => { v.controls = true; }); return; }
  const seen = new IntersectionObserver((entries) => entries.forEach((e) => {
    const v = e.target;
    if (e.isIntersecting) { v.preload = "auto"; v.play().catch(() => {}); } else { v.pause(); }
  }), { threshold: 0.35 });
  loops.forEach((v) => seen.observe(v));
})();
