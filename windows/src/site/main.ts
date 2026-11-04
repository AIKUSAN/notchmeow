// The site's cats: the Windows app's own engine and renderer (src/cat/), drawn on the home page next to a row of the sixteen coats. vite.site.config.ts bundles this into
// docs/assets/cats.js and cats.css. The page (docs/index.html) holds the markup; nothing here leaves the page: no request, no storage, no sound.

import "../theme.generated.css";
import { BotEngine } from "../cat/engine.ts";
import { cursorLook, newPose } from "../cat/geometry.ts";
import { VisibleLoop } from "../cat/loop.ts";
import { CAT_IDS, PRESETS } from "../cat/presets.ts";
import { drawCat, stillView } from "../cat/renderer.ts";
import { START, animates, dressing, pickCat, pickCoat } from "./rules.ts";
import type { Hero } from "./rules.ts";
import { startReactions } from "./react.ts";

interface Slot { engine: BotEngine; canvas: HTMLCanvasElement; name: HTMLElement; box: HTMLElement; button: HTMLButtonElement }

const dpr = () => Math.min(2, window.devicePixelRatio || 1);

function start(stage: HTMLElement, row: HTMLElement, hint: HTMLElement) {
  document.documentElement.classList.add("live");   // the page's CSS shows the stage, the coat row and the hint only once this script runs
  let hero: Hero = START;
  const slots: Slot[] = [...stage.querySelectorAll<HTMLElement>("[data-cat]")].map((box, i) => {
    const canvas = box.querySelector("canvas")!, button = box.querySelector("button")!, name = box.querySelector<HTMLElement>(".cat-name")!;
    const engine = new BotEngine(PRESETS[hero.coats[i]]);
    button.addEventListener("click", () => { hero = pickCat(hero, i); engine.emote("happy"); show(); });
    return { engine, canvas, name, box, button };
  });

  // The pointer, in viewport coordinates; null while it is off the page (or lifted, for a finger): the cats then look straight ahead.
  let pointer: { x: number; y: number } | null = null;
  addEventListener("pointermove", (e) => { pointer = { x: e.clientX, y: e.clientY }; });
  addEventListener("pointerup", (e) => { if (e.pointerType !== "mouse") pointer = null; });
  document.documentElement.addEventListener("mouseleave", () => { pointer = null; });

  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const page = { hidden: document.hidden, inView: true, reduced: reduce.matches };

  /** Draws one cat: sizes its canvas to its box, points its eyes at the pointer and draws. `dt` is 0 for a still frame. */
  const draw = (s: Slot, dt: number) => {
    const css = s.canvas.clientWidth;
    if (css < 2) return;
    const px = Math.round(css * dpr());
    if (s.canvas.width !== px || s.canvas.height !== px) { s.canvas.width = px; s.canvas.height = px; }
    const c = s.canvas.getContext("2d")!;
    c.setTransform(px / css, 0, 0, px / css, 0, 0);
    c.clearRect(0, 0, css, css);
    s.engine.particleOverhang = css * 0.2;
    if (pointer && dt > 0) {
      const r = s.canvas.getBoundingClientRect(), look = cursorLook(pointer.x - (r.left + r.width / 2), pointer.y - (r.top + r.height * 0.6));
      s.engine.lookX = look.x; s.engine.lookY = look.y;
    } else if (!pointer) { s.engine.lookX = 0; s.engine.lookY = 0; }
    if (dt > 0) s.engine.update(dt);
    s.engine.draw(c, css, css);
  };
  const drawStill = () => slots.forEach((s) => draw(s, 0));

  const loop = new VisibleLoop((dt) => slots.forEach((s) => draw(s, dt)), { raf: requestAnimationFrame.bind(window), caf: cancelAnimationFrame.bind(window), visible: () => animates(page) });
  /** The page's visibility or motion setting changed: start or stop the loop, and keep a still frame on a page that does not move. */
  const sync = () => { loop.sync(); if (page.reduced) drawStill(); };
  document.addEventListener("visibilitychange", () => { page.hidden = document.hidden; sync(); });
  reduce.addEventListener("change", (e) => { page.reduced = e.matches; sync(); });
  new IntersectionObserver((entries) => { page.inView = entries[entries.length - 1].isIntersecting; sync(); }).observe(stage);
  new ResizeObserver(() => { if (page.reduced) drawStill(); }).observe(stage);

  const thumbs = new Map<string, HTMLButtonElement>();

  /** The page follows `hero`: names, the picked cat's ring, the pressed coat and the line under the cats. */
  const show = () => {
    slots.forEach((s, i) => {
      const p = PRESETS[hero.coats[i]];
      s.name.textContent = p.label;
      s.button.setAttribute("aria-label", `${p.label}, ${p.desc || "cat"}: poke to say hello`);
      s.button.setAttribute("aria-pressed", String(hero.picked === i));
      s.box.classList.toggle("is-picked", hero.picked === i);
    });
    for (const [id, b] of thumbs) b.setAttribute("aria-pressed", String(hero.coats[hero.picked] === id));
    hint.textContent = dressing(hero);
    if (page.reduced) drawStill();
  };

  // The row of coats: a small still of each, drawn once.
  for (const id of CAT_IDS) {
    const b = document.createElement("button"), cv = document.createElement("canvas"), label = document.createElement("span");
    b.type = "button"; b.className = "coat"; b.setAttribute("aria-label", PRESETS[id].label);
    b.title = PRESETS[id].desc ? `${PRESETS[id].label}: ${PRESETS[id].desc}` : PRESETS[id].label;
    cv.setAttribute("aria-hidden", "true"); label.textContent = PRESETS[id].label;
    const w = 56, h = 52, k = dpr();
    cv.width = w * k; cv.height = h * k;
    const c = cv.getContext("2d")!;
    c.scale(k, k);
    drawCat(c, stillView(PRESETS[id], newPose()), w / 2, h / 2 + 1, 38);
    b.append(cv, label);
    b.addEventListener("click", () => {
      const was = hero;
      hero = pickCoat(hero, id);
      if (hero === was) return;
      slots[hero.picked].engine.setCoat(id);
      slots[hero.picked].engine.emote("happy");
      show();
    });
    thumbs.set(id, b);
    row.append(b);
  }
  show();
  sync();
}

const stage = document.getElementById("stage"), row = document.getElementById("coats"), hint = document.getElementById("hint");
if (stage && row && hint) start(stage, row, hint);
const reactions = document.getElementById("react");
if (reactions) startReactions(reactions);
