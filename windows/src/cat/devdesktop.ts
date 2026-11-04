// The `?dev` page's "Desktop cat" panel (sub-project H): the desktop cat at Small, Medium and Large on a mock desktop (with its badge, collar and kittens), the flight as a strip of
// frames (out, and out then turned round by an alert that clears), and the frame-time bench with the CPU each frame rate would cost. Open http://127.0.0.1:1420/?dev with `npx vite`
// (no Tauri window needed). Only the dev server serves it: main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { DESKTOP_FPS, DESKTOP_SIZES, desktopFlightAt } from "./desktop.ts";
import type { DesktopSizeId } from "./desktop.ts";
import { bigCatCollar } from "./collar.ts";
import { drawDesktopCat } from "./desktopdraw.ts";
import type { DesktopLook } from "./desktopdraw.ts";
import { desktopWindowLayout, kittenSide } from "./desktopview.ts";
import { BotEngine, catCfg } from "./engine.ts";
import { KittenPool } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";
import { PRESETS } from "./presets.ts";
import type { StateName } from "./base.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const COLLAR = AGENT_PILL_COLORS.agent_gemini;
const DESK_W = 900, DESK_H = 330;

function fit(cv: HTMLCanvasElement, w: number, h: number): CanvasRenderingContext2D {
  const dpr = Math.min(2, devicePixelRatio || 1);
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
  cv.style.width = `${w}px`; cv.style.height = `${h}px`;
  const c = cv.getContext("2d")!;
  c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, w, h);
  return c;
}
function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}
function section(title: string, note: string): HTMLElement {
  const s = document.createElement("section");
  s.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  s.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">${title}</h2><p style="color:${B.dim};margin:0 0 12px;font-size:13px">${note}</p>`;
  return s;
}
function row(label: string): HTMLElement {
  const r = document.createElement("div");
  r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:8px";
  const h = document.createElement("span");
  h.style.cssText = `font-size:12px;color:${B.dim};width:72px;flex:none`; h.textContent = label;
  r.append(h);
  return r;
}
function choice<T>(label: string, items: readonly (readonly [T, string])[], get: () => T, set: (v: T) => void): HTMLElement {
  const r = row(label), bs: [HTMLButtonElement, T][] = [];
  const sync = () => bs.forEach(([b, v]) => { b.style.borderColor = get() === v ? B.accent : B.line; b.style.color = get() === v ? B.accent : B.ink; });
  for (const [v, l] of items) { const b = button(l, () => { set(v); sync(); }); bs.push([b, v]); r.append(b); }
  sync();
  return r;
}

/** Kittens for the mock: `n` of them, the first waiting on an approval, the second searching, one leaving when there are four or more. */
const kittensOf = (n: number): Kitten[] => Array.from({ length: n }, (_, i) => ({ id: `k${i}`, type: "Explore", session: null, state: i === 0 ? "approval" : i === 1 ? "searching" : i === 3 ? "leaving" : "working", born: i, last: i, until: null }));

/** The wallpaper, a menu bar, three fake windows and the notch's strip, behind the cats. */
function drawDesktop(c: CanvasRenderingContext2D) {
  const g = c.createLinearGradient(0, 0, DESK_W, DESK_H);
  g.addColorStop(0, "#3b4a6b"); g.addColorStop(1, "#7a5c8a");
  c.fillStyle = g; c.fillRect(0, 0, DESK_W, DESK_H);
  c.fillStyle = "rgba(0,0,0,.35)"; c.fillRect(0, 0, DESK_W, 24);
  for (const [x, y, w, h] of [[40, 50, 330, 200], [330, 90, 300, 190], [600, 60, 270, 230]]) {
    c.fillStyle = "#e8e9ec"; c.beginPath(); c.roundRect(x, y, w, h, 8); c.fill();
    c.fillStyle = "#c9cbd1"; c.beginPath(); c.roundRect(x, y, w, 22, [8, 8, 0, 0]); c.fill();
    c.fillStyle = "#b6b8bf"; for (let i = 0; i < 5; i++) c.fillRect(x + 14, y + 40 + i * 24, w * (0.45 + 0.08 * ((i * 3) % 5)), 8);
  }
  c.fillStyle = "#000"; c.beginPath(); c.roundRect(DESK_W / 2 - 144, 0, 288, 32, [0, 0, 14, 14]); c.fill();
  c.fillStyle = "rgba(0,0,0,.45)"; c.fillRect(0, DESK_H - 30, DESK_W, 30);
}

/** Puts the "Desktop cat" panel into the `?dev` page before `before`, and registers its live drawing in `ticks`. */
export function mountDesktopDev(root: HTMLElement, before: HTMLElement, ticks: (() => void)[]): void {
  // ── The cats on a mock desktop ──
  const box = section("Desktop cat", "The big cat on the desktop at Small (Ø48), Medium (Ø64, the default) and Large (Ø96): its badge, its collar and its agent's kittens (up to three, then +N); in the right half of the screen the kittens stand on the left. The black strip at the top is the notch's.");
  const st = { coat: "shrimpy", state: null as StateName | null, kittens: 5, collar: true, outfit: null as string | null };
  const spots: { id: DesktopSizeId; x: number; y: number }[] = [{ id: "small", x: 140, y: 190 }, { id: "medium", x: 400, y: 190 }, { id: "large", x: 740, y: 180 }];
  const own: Record<DesktopSizeId, StateName> = { small: "approval", medium: "working", large: "working" };
  // The mock's own cfg, a copy of the shared one: dev.ts's Collar row writes the shared catCfg every tick, so the panel's collar style lives here.
  const mockCfg = { ...catCfg };
  const cats = spots.map((s) => ({ ...s, e: new BotEngine(PRESETS[st.coat], { state: own[s.id], cfg: mockCfg }), pool: new KittenPool(), shown: own[s.id] as StateName }));
  const cv = document.createElement("canvas");
  cv.id = "desktop-mock"; cv.setAttribute("aria-label", "The desktop cat at three sizes on a mock desktop"); cv.style.cssText = "display:block;border-radius:12px;margin-top:12px;max-width:100%";
  box.append(
    choice("Coat", (["shrimpy", "momo", "ginger", "midnight", "snow"] as const).map((c) => [c, PRESETS[c].label] as const), () => st.coat, (v) => { st.coat = v; }),
    choice("State", ([null, "idle", "working", "searching", "approval", "question", "error", "finished", "sleeping"] as const).map((s) => [s, s ?? "each its own"] as const), () => st.state, (v) => { st.state = v; }),
    choice("Kittens", ([0, 1, 3, 5, 8] as const).map((n) => [n, String(n)] as const), () => st.kittens, (v) => { st.kittens = v; }),
    choice("Collar", ([[true, "on"], [false, "off"]] as const), () => st.collar, (v) => { st.collar = v; }),
    choice("Outfit", ([null, "partyhat", "witchhat", "bunnyears", "sunglasses", "crown", "scarf", "bell"] as const).map((o) => [o, o ?? "none"] as const), () => st.outfit, (v) => { st.outfit = v; }),
    cv,
  );
  let last = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const c = fit(cv, DESK_W, DESK_H);
    drawDesktop(c);
    const t = now / 1000;
    mockCfg.collar = st.collar ? "band" : "off";
    for (const cat of cats) {
      const want = st.state ?? own[cat.id];
      if (cat.shown !== want) { cat.e.setState(want); cat.shown = want; }
      const side = kittenSide(cat.x, 0, DESK_W), lay = desktopWindowLayout(cat.id, st.coat, st.kittens, side);
      const look: DesktopLook = { coat: st.coat, collar: st.collar ? bigCatCollar(want, COLLAR) : null, kittens: kittensOf(st.kittens), lookX: Math.sin(t * 0.7), lookY: Math.sin(t * 0.5) * 0.3, dancing: false, pill: "dev", outfit: st.outfit };
      c.save(); c.translate(cat.x - lay.headX, cat.y - lay.headY);
      c.strokeStyle = "rgba(255,255,255,.35)"; c.setLineDash([4, 3]); c.strokeRect(0, 0, lay.w, lay.h); c.setLineDash([]);
      drawDesktopCat(c, cat.e, cat.pool, lay, look, dt);
      c.restore();
      c.fillStyle = "rgba(255,255,255,.9)"; c.font = `600 12px ${FONT}`; c.textAlign = "center"; c.fillText(`${cat.id} Ø${DESKTOP_SIZES[cat.id]}`, cat.x, cat.y + lay.D / 2 + 46);
    }
  });
  root.insertBefore(box, before);

  // ── The alert flight as a strip of frames ──
  const fbox = section("The alert flight", "An approval arrives while the cat is on the desktop (so does a file dragged onto the notch: the same alert to the cat, which flies in to catch the file and flies back when the catch is over): it gives the surprised emote, flies to its spot in the notch (0.6 s: an arc, eased in and out, at full size the whole way), waits while you answer, then flies back out to where it was. Eight frames, each the mock desktop at half size; the times are from the approval.");
  const fcv = document.createElement("canvas");
  fcv.id = "desktop-flight"; fcv.setAttribute("aria-label", "The alert flight as a strip of eight frames"); fcv.style.cssText = "display:block;border-radius:12px;margin-top:12px;max-width:100%";
  fbox.append(fcv);
  const PW = DESK_W / 2, PH = DESK_H / 2;
  function drawFlights() {
    const c = fit(fcv, DESK_W, PH * 4), desk = { x: 640, y: 215 }, notch = { x: DESK_W / 2, y: 16 };
    let clock = 0;
    const lay = desktopWindowLayout("medium", st.coat, 0, 1);
    const cat = new BotEngine(PRESETS[st.coat], { quiet: true, now: () => clock, rand: () => 0.5 }), pool = new KittenPool();
    const step = (ms: number) => { for (let n = 0; n < Math.round(ms / 16.7); n++) { clock += 16.7; cat.update(1 / 60); } };
    const small = new BotEngine(PRESETS[st.coat], { mini: true, quiet: true, now: () => clock, rand: () => 0.5 });
    const frames: { label: string; at: { x: number; y: number } | null; emote?: boolean }[] = [
      { label: "0 ms: on the desktop", at: desk },
      { label: "300 ms: an approval arrives, surprised", at: desk, emote: true },
      { label: "750 ms: flying in, t 0.25", at: desktopFlightAt(desk, notch, 0.25) },
      { label: "900 ms: t 0.5", at: desktopFlightAt(desk, notch, 0.5) },
      { label: "1050 ms: t 0.75", at: desktopFlightAt(desk, notch, 0.75) },
      { label: "1350 ms: in the notch while you answer", at: null },
      { label: "answered + 300 ms: flying out, t 0.5", at: desktopFlightAt(notch, desk, 0.5) },
      { label: "answered + 600 ms: back on the desktop", at: desk },
    ];
    frames.forEach((f, i) => {
      const x0 = (i % 2) * PW, y0 = Math.floor(i / 2) * PH;
      c.save(); c.beginPath(); c.rect(x0, y0, PW, PH); c.clip(); c.translate(x0, y0); c.scale(0.5, 0.5);
      drawDesktop(c);
      if (f.at) {
        if (f.emote) cat.emote("surprised");
        step(f.emote ? 250 : 16);
        c.save(); c.translate(f.at.x - lay.headX, f.at.y - lay.headY);
        drawDesktopCat(c, cat, pool, lay, { coat: st.coat, collar: COLLAR, kittens: [], lookX: 0.2, lookY: 0.1, dancing: false, pill: "dev" }, 0);
        c.restore();
      } else {
        step(16); small.update(1 / 60);
        const w = 20 / 0.6;
        c.save(); c.translate(notch.x - w / 2, notch.y - w / 2); small.draw(c, w, w); c.restore();
      }
      c.restore();
      c.fillStyle = "rgba(0,0,0,.55)"; c.fillRect(x0 + 6, y0 + PH - 24, PW - 12, 18);
      c.fillStyle = "#fff"; c.font = `600 11px ${FONT}`; c.textAlign = "left"; c.fillText(f.label, x0 + 12, y0 + PH - 11);
      c.strokeStyle = "rgba(255,255,255,.25)"; c.strokeRect(x0 + 0.5, y0 + 0.5, PW - 1, PH - 1);
    });
  }
  drawFlights();
  fbox.append(button("Redraw with the chosen coat", drawFlights));
  root.insertBefore(fbox, before);

  // ── The bench ──
  const bbox = section("Frame time and CPU", `One frame of the desktop cat with no kittens and with three kittens at each size, drawn in this browser's software canvas (slower than the app's, so the numbers err on the high side), and what each frame rate would cost: ms per frame x frames per second / 10 = % of one core. Rates: asleep ${DESKTOP_FPS.asleep}, idle ${DESKTOP_FPS.idle}, working or the cursor near ${DESKTOP_FPS.active}, motion ${DESKTOP_FPS.motion}. Target: under 1 % idle without kittens and about 0 % asleep; 5 fps with three kittens is reported, not held.`);
  const note = document.createElement("pre");
  note.id = "desktop-bench"; note.style.cssText = `color:${B.ink};font-size:12px;margin:10px 0 0;white-space:pre-wrap`; note.textContent = "Press Measure.";
  const median = (a: number[]) => [...a].sort((x, y) => x - y)[a.length >> 1];
  const once = (id: DesktopSizeId, frames: number, kittens = 3, outfit: string | null = null): number => {
    const e = new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 }), pool = new KittenPool(), lay = desktopWindowLayout(id, "shrimpy", kittens, 1);
    const c = fit(document.createElement("canvas"), lay.w, lay.h), look: DesktopLook = { coat: "shrimpy", collar: COLLAR, kittens: kittensOf(kittens), lookX: 0.2, lookY: 0, dancing: false, pill: "bench", outfit }, t0 = performance.now();
    for (let f = 0; f < frames; f++) drawDesktopCat(c, e, pool, lay, look, 1 / 60);
    return (performance.now() - t0) / frames;
  };
  const measure = () => {
    const lines = ["size   kittens  ms/frame   asleep   idle     working  motion   (% of one core)"];
    for (const id of ["small", "medium", "large"] as const) for (const n of [0, 3]) {
      once(id, 20, n);
      const ms = median([once(id, 60, n), once(id, 60, n), once(id, 60, n)]), pct = (fps: number) => ((ms * fps) / 10).toFixed(2).padStart(6);
      lines.push(`${id.padEnd(7)}${String(n).padStart(4)}${ms.toFixed(2).padStart(11)}   ${pct(DESKTOP_FPS.asleep)}   ${pct(DESKTOP_FPS.idle)}   ${pct(DESKTOP_FPS.active)}   ${pct(DESKTOP_FPS.motion)}`);
    }
    lines.push("", "With the witch hat on (the tallest outfit; an outfit adds no motion, so the frame rates are the same):");
    for (const id of ["small", "medium", "large"] as const) {
      once(id, 20, 3, "witchhat");
      const bare = median([once(id, 60, 3), once(id, 60, 3), once(id, 60, 3)]), worn = median([once(id, 60, 3, "witchhat"), once(id, 60, 3, "witchhat"), once(id, 60, 3, "witchhat")]);
      lines.push(`${id.padEnd(7)} bare ${bare.toFixed(2)} ms, dressed ${worn.toFixed(2)} ms per frame (${(worn - bare >= 0 ? "+" : "") + (worn - bare).toFixed(2)} ms)`);
    }
    lines.push("", "The cursor check (about 10 Hz) and the fullscreen check (2 Hz) run in Rust while the cat is awake: their cost is the owner's number from Task Manager.");
    note.textContent = lines.join("\n");
  };
  const brow = row("Bench");
  const run = button("Measure the desktop cat", measure);
  run.id = "desktop-bench-run";
  brow.append(run);
  bbox.append(brow, note);
  root.insertBefore(bbox, before);
}
