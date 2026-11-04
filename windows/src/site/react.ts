// The site's "How the cats react" section (docs/index.html): one large live cat, the eight states the notch shows as buttons, Poke and Try an outfit.
// The cat is the app's own engine, the one the hero draws. The words and the outfit steps are rules.ts's. The section has its own loop, which runs only
// while its cat is on screen (the same rule as the hero's); under reduced motion a state click, a poke or an outfit draws one still frame.
// Nothing leaves the page: no request, no storage, no sound.

import { BotEngine } from "../cat/engine.ts";
import { VisibleLoop } from "../cat/loop.ts";
import { PRESETS } from "../cat/presets.ts";
import { REACTIONS, TRY_OUTFITS, animates, nextOutfit, outfitWords } from "./rules.ts";
import type { PageState } from "./rules.ts";

const dpr = () => Math.min(2, window.devicePixelRatio || 1);

/** Runs the engine for `ms` on its own clock, unseen, so the state's pose, tint and badge have settled: the one still frame a reduced-motion visitor sees. */
export function settle(e: BotEngine, clock: { t: number }, ms = 3000): void {
  const step = 1000 / 60;
  for (let t = 0; t < ms; t += step) { clock.t += step; e.update(1 / 60); }
}

/** Wires the section under `root`. A missing piece changes nothing: the section then shows its words and no cat. */
export function startReactions(root: HTMLElement): void {
  const canvas = root.querySelector("canvas"), cat = root.querySelector<HTMLButtonElement>(".react-cat");
  const line = root.querySelector<HTMLElement>("[data-line]"), note = root.querySelector<HTMLElement>("[data-outfit-note]");
  const states = [...root.querySelectorAll<HTMLButtonElement>("button[data-state]")];
  const poke = root.querySelector<HTMLButtonElement>("button[data-action='poke']"), outfit = root.querySelector<HTMLButtonElement>("button[data-action='outfit']");
  if (!canvas || !cat || !line || !note || !poke || !outfit || states.length !== REACTIONS.length) return;

  document.documentElement.classList.add("live");   // the section's controls show only once this runs (the page's CSS)
  // The engine's clock is ours: the loop advances it by each frame, and `settle` by its own steps, so a still frame never waits on real time.
  const clock = { t: 0 };
  const engine = new BotEngine(PRESETS.shrimpy, { now: () => clock.t });
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const page: PageState = { hidden: document.hidden, inView: false, reduced: reduce.matches };
  let outfitStep = TRY_OUTFITS.indexOf(null);   // the cat starts bare

  /** Draws the cat into its canvas at the canvas's size. */
  const paint = () => {
    const css = canvas.clientWidth;
    if (css < 2) return;
    const px = Math.round(css * dpr());
    if (canvas.width !== px || canvas.height !== px) { canvas.width = px; canvas.height = px; }
    const c = canvas.getContext("2d")!;
    c.setTransform(px / css, 0, 0, px / css, 0, 0);
    c.clearRect(0, 0, css, css);
    engine.particleOverhang = css * 0.2;
    engine.draw(c, css, css);
  };
  const loop = new VisibleLoop((dt) => { clock.t += dt * 1000; engine.update(dt); paint(); }, {
    raf: requestAnimationFrame.bind(window), caf: cancelAnimationFrame.bind(window), visible: () => animates(page),
  });
  /** One still frame, drawn only while the cat is on screen. */
  const still = () => { if (page.inView) paint(); };
  /** The page's visibility, motion or position changed: run or stop the loop, and keep a still frame for a page that does not move. */
  const sync = () => { loop.sync(); if (page.reduced) still(); };
  document.addEventListener("visibilitychange", () => { page.hidden = document.hidden; sync(); });
  reduce.addEventListener("change", (e) => { page.reduced = e.matches; sync(); });
  new IntersectionObserver((entries) => { page.inView = entries[entries.length - 1].isIntersecting; sync(); }).observe(canvas);
  new ResizeObserver(() => { if (page.reduced) still(); }).observe(canvas);

  /** Sets the cat to a state, presses its button and shows its sentence under the cat. An unknown state changes nothing. */
  const show = (state: string) => {
    const r = REACTIONS.find((x) => x.state === state);
    if (!r) return;
    engine.setState(r.state);
    for (const b of states) b.setAttribute("aria-pressed", String(b.dataset.state === r.state));
    line.textContent = r.line;
    if (page.reduced) { settle(engine, clock); still(); }
  };
  const pokeCat = () => {
    engine.emote("happy");
    if (page.reduced) { settle(engine, clock, 1500); still(); }
  };
  const tryOutfit = () => {
    outfitStep = nextOutfit(outfitStep);
    const id = TRY_OUTFITS[outfitStep];
    engine.outfit = id;
    note.textContent = outfitWords(id);
    if (page.reduced) still();
  };

  for (const b of states) b.addEventListener("click", () => show(b.dataset.state ?? ""));
  cat.addEventListener("click", pokeCat);
  poke.addEventListener("click", pokeCat);
  outfit.addEventListener("click", tryOutfit);
  show(REACTIONS[0].state);
  sync();
}
