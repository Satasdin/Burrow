// The home page's motion: the night sky behind the hero (the app's own Ember sky), the screenshot tilting flat as it
// rises, sections that settle in as they arrive, the pinned app window that follows the story, and the result bars.
// Everything here is decoration: with Reduce Motion, or without this script, the page reads the same, standing still.
(() => {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  document.documentElement.classList.add("js");

  // ---------------------------------------------------------------- arrive
  const arrive = document.querySelectorAll("[data-reveal]");
  if (still || !("IntersectionObserver" in window)) arrive.forEach((e) => e.classList.add("in"));
  else {
    const seen = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add("in"); seen.unobserve(e.target); }
    }), {rootMargin: "0px 0px -8% 0px"});
    arrive.forEach((e) => seen.observe(e));
  }

  // ---------------------------------------------------------------- the night sky
  const sky = document.querySelector(".sky");
  if (sky && !still) {
    const ctx = sky.getContext("2d");
    let w = 0, h = 0, on = true;
    let seed = 11; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const stars = Array.from({length: 170}, () => ({x: rnd(), y: rnd(), r: .4 + rnd() * 1.3, t: rnd() * 6.3, s: .4 + rnd() * 1.2, warm: rnd() < .35}));
    const size = () => {
      const r = sky.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
      w = r.width; h = r.height; sky.width = w * dpr; sky.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    new ResizeObserver(size).observe(sky); size();
    new IntersectionObserver((e) => { on = e[0].isIntersecting; }).observe(sky);
    const draw = (now) => {
      if (on) {
        ctx.clearRect(0, 0, w, h);
        for (const s of stars) {
          const a = .25 + .55 * (.5 + .5 * Math.sin(now / 1000 * s.s + s.t));
          ctx.fillStyle = s.warm ? `rgba(255,176,90,${a})` : `rgba(230,230,255,${a * .8})`;
          ctx.beginPath(); ctx.arc(s.x * w, (s.y * h + now / 400 * s.s) % h, s.r, 0, 7); ctx.fill();
        }
      }
      requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  // ---------------------------------------------------------------- the hero screenshot lies flat as it rises
  const tilt = document.querySelector("[data-tilt]");
  if (tilt && !still) {
    let ticking = false;
    const set = () => {
      ticking = false;
      const r = tilt.getBoundingClientRect(), vh = innerHeight;
      const p = Math.min(1, Math.max(0, (vh - r.top) / (vh * .9)));   // 0 when it enters, 1 once it is well up
      tilt.style.setProperty("--p", p.toFixed(3));
    };
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(set); } }, {passive: true});
    set();
  }

  // ---------------------------------------------------------------- the story: the pinned window follows the step you read
  const steps = [...document.querySelectorAll(".step")];
  const shots = [...document.querySelectorAll(".stage-frame img")];
  const dots = [...document.querySelectorAll(".stage-dots i")];
  if (steps.length && shots.length && "IntersectionObserver" in window) {
    const show = (i) => {
      shots.forEach((s, j) => s.classList.toggle("on", j === i));
      dots.forEach((d, j) => d.classList.toggle("on", j === i));
      steps.forEach((s, j) => s.classList.toggle("on", j === i));
    };
    const watch = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (e.isIntersecting) show(+e.target.dataset.step);
    }), {rootMargin: "-45% 0px -45% 0px"});
    steps.forEach((s) => watch.observe(s));
    show(0);
  }

  // ---------------------------------------------------------------- results count up as they arrive
  const counts = document.querySelectorAll("[data-count]");
  if (!still && "IntersectionObserver" in window) {
    counts.forEach((c) => { c.textContent = "0"; });
    const go = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (!e.isIntersecting) return;
      go.unobserve(e.target);
      const el = e.target, end = +el.dataset.count, t0 = performance.now();
      const step = (now) => {
        const k = Math.min(1, (now - t0) / 1400), eased = 1 - Math.pow(1 - k, 3);
        el.textContent = Math.round(end * eased);
        if (k < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }), {threshold: .6});
    counts.forEach((c) => go.observe(c));
  }
})();
