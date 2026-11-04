// The `?dev` page: the cat contact sheet. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window
// needed) and look at every coat at every size, next to design/prototype/notchmeow.html.
// Only the dev server serves it: main.ts loads this module behind `import.meta.env.DEV`, so a release
// build does not contain it.

import { cursorLook, newPose } from "./geometry.ts";
import { drawCat, stillView } from "./renderer.ts";
import type { CatView } from "./renderer.ts";
import { CAT_IDS, PRESETS, kittenOf } from "./presets.ts";
import { STATES } from "./base.ts";
import type { StateName } from "./base.ts";
import { BotEngine, catCfg } from "./engine.ts";
import { PERSONAS, personaNamed } from "./personality.ts";
import { FLIGHT_MS, flightAt } from "./geometry.ts";
import { drawFileIcon } from "./renderer.ts";
import { Greeting } from "./greeting.ts";
import { KittenPool, drawKittens } from "./kittendraw.ts";
import { mountDesktopDev } from "./devdesktop.ts";
import { mountWardrobeDev } from "./devwardrobe.ts";
import { mountShelfDev } from "../shelf/devshelf.ts";
import { mountLinkDev } from "../link/devlink.ts";
import { mountCompanionDev } from "../companion/devcompanion.ts";
import { mountProjectsDev } from "../projects/devprojects.ts";
import { mountSettingsDev } from "../settings/devpanel.ts";
import type { Kitten } from "./kittens.ts";
import { bigCatCollar } from "./collar.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

/** The ladder: head widths from the mini pills to the expanded island, then two kitten sizes. */
const SIZES = [
  { d: 12, l: "Ø12 mini" }, { d: 16, l: "Ø16" }, { d: 20, l: "Ø20 compact" }, { d: 24, l: "Ø24" }, { d: 28, l: "Ø28 full" },
  { d: 44, l: "Ø44" }, { d: 66, l: "Ø66 expanded" }, { d: 16, l: "kitten Ø16", kit: true }, { d: 40, l: "kitten Ø40", kit: true },
];
const slotW = (d: number) => Math.max(62, d * 2.2);
const LW = SIZES.reduce((a, z) => a + slotW(z.d), 0) + 24;
const ROWH = 150;

interface Cell { d: number; l: string; v: CatView }
interface Row { id: string; cells: Cell[] }

function rr(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  c.beginPath(); c.roundRect(x, y, w, h, r);
}

/** A canvas sized for the screen's pixel ratio; returns its 2D context ready to draw in CSS px. */
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

/** A group of buttons of which one is on. */
function choice<T>(label: string, items: readonly (readonly [T, string])[], get: () => T, set: (v: T) => void): HTMLElement {
  const r = row(label), bs: [HTMLButtonElement, T][] = [];
  const sync = () => bs.forEach(([b, v]) => { b.style.borderColor = get() === v ? B.accent : B.line; b.style.color = get() === v ? B.accent : B.ink; });
  for (const [v, l] of items) { const b = button(l, () => { set(v); sync(); }); bs.push([b, v]); r.append(b); }
  sync();
  return r;
}

export function mountDev(root: HTMLElement): void {
  document.title = "NotchMeow cat sheet";
  Object.assign(document.body.style, { background: B.page, overflow: "auto", height: "auto", userSelect: "text", cursor: "auto" });
  Object.assign(root.style, { position: "static", inset: "auto", padding: "20px 16px 56px", font: `14px/1.5 ${FONT}`, color: B.ink });

  const head = document.createElement("div");
  head.innerHTML = `<h1 style="font-size:22px;font-weight:600;margin:0 0 4px">NotchMeow cat sheet</h1>
    <p style="color:${B.dim};margin:0 0 14px">Every coat at every size, in the compact and full drawing, with kittens. Move the pointer over the page: the cats turn to follow it.
    Ears are scaled to 0.8 at Ø20 and below (provisional) and below Ø28 the fills are flat (no gradients): the prototype page draws both the same way (A-0b).</p>`;
  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:14px";
  const state = { fur: false, tint: true, collar: "off", col: AGENT_PILL_COLORS.agent_gemini };
  /** The collar a cat that always wears one (the ladder, the pills) is drawn with. */
  const worn = () => (state.collar === "off" ? null : { style: state.collar, col: state.col });
  const toggle = (label: string, on: boolean, set: (v: boolean) => void) => {
    const b = document.createElement("button");
    b.style.cssText = BTN;
    const sync = () => { b.textContent = `${label}: ${on ? "on" : "off"}`; b.style.borderColor = on ? B.accent : B.line; };
    b.onclick = () => { on = !on; set(on); sync(); };
    sync();
    bar.append(b);
  };
  toggle("Fur lines", state.fur, (v) => (state.fur = v));
  toggle("State tint", state.tint, (v) => (state.tint = v));
  root.append(head, bar);

  let mx: number | null = null, my = 0;
  document.addEventListener("pointermove", (ev) => { mx = ev.clientX; my = ev.clientY; });
  document.documentElement.addEventListener("mouseleave", () => { mx = null; });
  /** The pointer's gaze from a point on the page, -1…1, or rest when the pointer is off the page. */
  const gazeFrom = (px: number, py: number) => (mx === null ? { x: 0, y: 0 } : cursorLook(mx - px, my - py));
  const ticks: (() => void)[] = [];
    /** What to redo when the cat or the motion style changes. */
  const rebuilds: (() => void)[] = [];
  const rebuildAll = () => rebuilds.forEach((r) => r());
  /** The drawing time of the still sheet and of the live cats, in ms per frame, smoothed. */
  let sheetMs = 0, liveMs = 0;

  // ── The ladder, one row per coat ──
  const rows: Row[] = CAT_IDS.map((id) => ({
    id,
    cells: SIZES.map((z) => ({ ...z, v: stillView(z.kit ? kittenOf(PRESETS[id]) : PRESETS[id], newPose()) })),
  }));
  const wrap = document.createElement("div");
  wrap.style.cssText = "overflow-x:auto;padding-bottom:4px";
  const lad = document.createElement("canvas");
  lad.setAttribute("aria-label", "Every coat at every size");
  lad.style.display = "block";
  wrap.append(lad);
  root.append(wrap);

  function drawLadder() {
    const c = fit(lad, LW, ROWH * rows.length), box = lad.getBoundingClientRect();
    rows.forEach((r, ri) => {
      const top = ri * ROWH;
      c.fillStyle = B.ink; c.font = `600 12px ${FONT}`; c.textAlign = "left"; c.textBaseline = "top"; c.fillText(PRESETS[r.id].label + (PRESETS[r.id].desc ? ` · ${PRESETS[r.id].desc}` : ""), 12, top + 4);
      let x = 12;
      for (const cell of r.cells) {
        const w = slotW(cell.d), cx = x + w / 2, cy = top + 20 + ROWH * 0.42;
        if (cell.l === "kitten Ø16") { c.strokeStyle = B.line; c.beginPath(); c.moveTo(x, top + 26); c.lineTo(x, top + ROWH - 14); c.stroke(); }
        c.fillStyle = "#000"; rr(c, x + 4, top + 22, w - 8, ROWH - 46, 10); c.fill();
        // The cat looks at the pointer (no smoothing: these are stills).
        const g = gazeFrom(box.left + cx, box.top + cy);
        cell.v.s.yaw = g.x * 0.62; cell.v.s.pitch = g.y * 0.5;
        drawCat(c, cell.v, cx, cy, cell.d, { tint: state.tint, fur: state.fur && cell.d >= 60, collar: worn() });
        c.fillStyle = B.dim; c.font = `11px ${FONT}`; c.textAlign = "center"; c.textBaseline = "alphabetic"; c.fillText(cell.l, cx, top + ROWH - 8);
        x += w;
      }
    });
  }
  ticks.push(drawLadder);

    // ── Stage 2: the 11 states, live, in either motion style ──
  // ── Stage 6: the collar ──
  const STYLES: readonly (readonly [string, string])[] = [["off", "Off"], ["tag", "Band and tag"], ["band", "Band"], ["kerchief", "Neckerchief"]];
  const AGENTS: readonly (readonly [string, string])[] = [
    ["#F5F6F8", "Claude Code pill"], ["#8AB4F8", "Gemini CLI"], ["#E879F9", "Antigravity"], ["#22C55E", "Resend"], ["#0570DE", "Stripe"],
  ];
  const collarBox = section("Collar", "The agent colour as a thin collar, at every size from Ø12 up, never under 3 px of band, a 6 px tag or a 7 by 5 px neckerchief on the screen. The coat ladder wears it as the pills and the compact grid do; the States strip, the big cat and the Compact notch wear it by the island's rule: none while idle, asleep or dizzy.");
  collarBox.append(
    choice("Style", STYLES, () => state.collar, (v) => { state.collar = v; }),
    choice("Agent", AGENTS, () => state.col, (v) => { state.col = v; }),
  );
  root.insertBefore(collarBox, wrap);
  ticks.push(() => { catCfg.collar = state.collar; });

  const dev = { cat: "shrimpy", motion: "playful" };
  const statesBox = section("States", "Each cat is a live engine drawn the way the island draws it (engine.draw). Click a cat to poke it; three quick pokes make it dizzy.");
  const strip = document.createElement("div");
  strip.style.cssText = "display:flex;flex-wrap:wrap;gap:10px;margin-top:12px";
  statesBox.append(
    choice("Cat", CAT_IDS.map((id) => [id, PRESETS[id].label] as const), () => dev.cat, (v) => { dev.cat = v; rebuildAll(); }),
    choice("Motion", [["playful", "Playful"], ["classic", "Classic"]] as const, () => dev.motion, (v) => { dev.motion = v; catCfg.motion = v; rebuildAll(); }),
    (() => {
      // The sleeping cat of the strip: wake it to see what Playful does (zoomies after 220 ms) and what Classic does (nothing).
      const r = row("Sleep");
      const sleeper = () => live.find((l) => l.st === "sleeping")?.e;
      r.append(button("Wake the sleeping cat", () => sleeper()?.setState("idle")), button("Put it back to sleep", () => sleeper()?.setState("sleeping")));
      return r;
    })(),
    strip,
  );
  const readout = document.createElement("p");
  readout.style.cssText = `color:${B.dim};font-size:12px;margin:10px 0 0`;
  statesBox.append(readout);
  root.insertBefore(statesBox, wrap);

  interface Live { st: StateName; e: BotEngine; cv: HTMLCanvasElement }
  let live: Live[] = [];
  function buildStrip() {
    strip.replaceChildren();
    live = STATES.map((st) => {
      const e = new BotEngine(PRESETS[dev.cat], { state: st });
      const fig = document.createElement("figure");
      fig.style.cssText = "margin:0;background:#000;border-radius:12px;padding-bottom:6px;text-align:center";
      const cv = document.createElement("canvas");
      cv.style.cursor = "pointer";
      cv.onpointerdown = () => e.slap();
      const cap = document.createElement("figcaption");
      cap.style.cssText = `font-size:11px;color:${B.dim}`; cap.textContent = st;
      fig.append(cv, cap); strip.append(fig);
      return { st, e, cv };
    });
  }
  rebuilds.push(buildStrip);
  buildStrip();
  let last = performance.now();
  ticks.push(() => {
    const t0 = performance.now(), dt = Math.min(0.05, (t0 - last) / 1000);
    last = t0;
    for (const { e, cv } of live) {
      const W = 120, H = 130, c = fit(cv, W, H), box = cv.getBoundingClientRect();
      e.particleOverhang = 20;
      e.collarColor = state.collar === "off" ? null : bigCatCollar(e.state, state.col);
      const g = gazeFrom(box.left + W / 2, box.top + H / 2 + 10);
      e.lookX = g.x; e.lookY = g.y;
      e.update(dt);
      e.draw(c, W, H);
    }
    readout.textContent = `Drawing per frame: the ${live.length} live cats ${liveMs.toFixed(2)} ms (the Mac's budget is 2 ms for twelve small cats plus the big one), the still sheet ${sheetMs.toFixed(2)} ms.`;
  });

  // The compact strip: the island's resting strip, 288 by 32, with the cat at Ø20 and 40 px in. The canvas starts at the top of the strip, as the
  // screen starts at the top of the island, so an ear that rises above it is cut off. The ear fit is the contract's (A-0b, merged `6adf584`).
  const notchBox = section("Compact notch", "The island's resting strip (288 by 32, the cat at Ø20, badge on the left). Its top edge is the top of the screen, where an ear is cut off. With the ear fit on, the ears are shrunk just enough to stay under it; switch it off and press the Hop button to see the hop push them out.");
  const notch = { ears: true, state: "approval" as StateName };
  const notchCv = document.createElement("canvas");
  notchCv.id = "notch-strip";
  notchCv.style.cssText = "display:block;margin-top:12px;background:#3a3d44";
  let notchCat = new BotEngine(PRESETS[dev.cat], { state: notch.state });
  notchBox.append(
    choice("State", (["idle", "approval", "working", "finished", "dizzy"] as StateName[]).map((v) => [v, v] as const), () => notch.state, (v) => { notch.state = v; notchCat.setState(v); }),
    choice("Fit ears", [[true, "On"], [false, "Off"]] as const, () => notch.ears, (v) => { notch.ears = v; }),
    (() => {
      // The worst pose the fit is tested with: a high hop, ears up and the head tilted. Held for 1.5 s.
      const r = row("Pose");
      r.append(button("Hop, ears up", () => {
        notchCat.anim("oy", [[-0.3, 120, "out"], [-0.3, 1500, "lin"], [0, 200, "inOut"]]);
        notchCat.anim("earU", [[1.4, 120, "out"], [1.4, 1500, "lin"], [1, 200, "inOut"]]);
        notchCat.anim("tilt", [[0.24, 120, "out"], [0.24, 1500, "lin"], [0, 200, "inOut"]]);
      }));
      return r;
    })(),
    notchCv,
  );
  root.insertBefore(notchBox, wrap);
  rebuilds.push(() => { notchCat = new BotEngine(PRESETS[dev.cat], { state: notch.state }); });
  let notchLast = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - notchLast) / 1000);
    notchLast = now;
    const c = fit(notchCv, 288, 32);
    c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, 288, 32, [0, 0, 14, 14]); c.fill();
    notchCat.update(dt);
    const wear = state.collar === "off" ? null : bigCatCollar(notch.state, state.col);
    drawCat(c, notchCat, 40, 16, 20, { badgeSide: -1, earCeiling: notch.ears ? 0 : undefined, collar: wear ? { style: state.collar, col: wear } : null });
  });
  // ── Sub-project B: the small coloured eyes ──
  // Every coat and a kitten of it at the compact sizes, the flat ink pills they had (`eyes: "ink"`, left of each pair) beside the small coloured eyes (right). Drawn once:
  // the cats are stills. Scale 2 draws the compact drawing at twice the head width, so the eyes can be judged; scale 1 is true size.
  const EYE_COLS = [{ d: 12 }, { d: 16 }, { d: 20 }, { d: 24 }, { d: 12, kit: true }, { d: 16, kit: true }, { d: 20, kit: true }];
  const EYE_LEFT = 74, EYE_HEAD = 36;
  const eyeBox = section("Small eyes", "Every coat and a kitten of it at the compact sizes: the flat ink pills they had (left of each pair) beside the small coloured eyes (right). The first sheet is magnified 2 times, as the compact drawing at twice the size; the second is true size. Geometry: smallEye, pinned by small-eye-cases.json.");
  const eyeViews = new Map<string, CatView>();
  const eyeView = (id: string, kit: boolean): CatView => {
    const key = id + (kit ? ":k" : "");
    let v = eyeViews.get(key);
    if (!v) { v = stillView(kit ? kittenOf(PRESETS[id]) : PRESETS[id], newPose()); eyeViews.set(key, v); }
    return v;
  };
  function drawEyeSheet(cv: HTMLCanvasElement, scale: number) {
    const colW = EYE_COLS.map((z) => Math.max(80, z.d * scale * 2 + 34)), rowH = Math.max(34, 24 * scale + 10);
    const W = EYE_LEFT + colW.reduce((a, b) => a + b, 0) + 8, H = EYE_HEAD + CAT_IDS.length * rowH + 6, c = fit(cv, W, H);
    c.fillStyle = "#000"; c.fillRect(0, 0, W, H); c.textBaseline = "alphabetic"; c.textAlign = "center";
    let x = EYE_LEFT;
    EYE_COLS.forEach((z, i) => {
      const w = colW[i];
      c.fillStyle = "#ececee"; c.font = `600 11px ${FONT}`; c.fillText(`${z.kit ? "kitten " : ""}Ø${z.d}`, x + w / 2, 15);
      c.fillStyle = "#9a9ca3"; c.font = `10px ${FONT}`; c.fillText("ink · coloured", x + w / 2, 29);
      c.strokeStyle = "#2a2c31"; c.beginPath(); c.moveTo(x + 0.5, 6); c.lineTo(x + 0.5, H - 6); c.stroke();
      x += w;
    });
    CAT_IDS.forEach((id, ri) => {
      const cy = EYE_HEAD + ri * rowH + rowH / 2;
      c.fillStyle = "#ececee"; c.font = `11px ${FONT}`; c.textAlign = "left"; c.fillText(PRESETS[id].label, 10, cy + 4);
      let cx0 = EYE_LEFT;
      EYE_COLS.forEach((z, i) => {
        const w = colW[i];
        for (const [fx, ink] of [[0.27, true], [0.73, false]] as const) drawCat(c, eyeView(id, !!z.kit), cx0 + w * fx, cy, z.d * scale, { tint: false, badge: false, detail: "compact", eyes: ink ? "ink" : undefined });
        cx0 += w;
      });
    });
  }
  const eyes2 = document.createElement("canvas"), eyes1 = document.createElement("canvas");
  eyes2.id = "eyes2"; eyes1.id = "eyes1";
  eyes2.setAttribute("aria-label", "Small eyes, magnified 2 times"); eyes1.setAttribute("aria-label", "Small eyes, true size");
  for (const cv of [eyes2, eyes1]) { cv.style.display = "block"; }
  const eyes2Wrap = document.createElement("div"), eyes1Wrap = document.createElement("div");
  eyes2Wrap.style.cssText = "overflow-x:auto"; eyes1Wrap.style.cssText = "overflow-x:auto;margin-top:12px";
  eyes2Wrap.append(eyes2); eyes1Wrap.append(eyes1);
  // The cost of the eyes, in the same build: twelve small cats and one Ø66 drawn in turn, with the ink pills and with the coloured eyes, alternating over three rounds.
  const benchCv = document.createElement("canvas");
  const benchNote = document.createElement("p");
  benchNote.id = "eye-bench"; benchNote.style.cssText = `color:${B.dim};font-size:12px;margin:10px 0 0`; benchNote.textContent = "Press Measure to time twelve small cats and a Ø66 with ink and with coloured eyes.";
  const benchViews = CAT_IDS.slice(0, 12).map((id, i) => ({ v: stillView(PRESETS[id], newPose()), d: [12, 16, 20, 24][i % 4], x: 30 + i * 46 })).concat([{ v: stillView(PRESETS.shrimpy, newPose()), d: 66, x: 640 }]);
  function benchOnce(eyes: "ink" | undefined, frames: number): number {
    const c = fit(benchCv, 720, 90), t0 = performance.now();
    for (let f = 0; f < frames; f++) for (const b of benchViews) drawCat(c, b.v, b.x, 45, b.d, { eyes });
    return (performance.now() - t0) / frames;
  }
  const median = (a: number[]) => [...a].sort((x, y) => x - y)[a.length >> 1];
  const measure = () => {
    const ink: number[] = [], col: number[] = [];
    benchOnce(undefined, 20); benchOnce("ink", 20); // warm up
    for (let r = 0; r < 3; r++) { ink.push(benchOnce("ink", 120)); col.push(benchOnce(undefined, 120)); }
    const a = median(ink), b = median(col);
    benchNote.textContent = `Twelve small cats and one Ø66, drawn in turn: ink eyes ${a.toFixed(2)} ms, coloured eyes ${b.toFixed(2)} ms per frame (median of 3 rounds of 120 frames; ${(((b - a) / a) * 100).toFixed(0)}% more).`;
  };
  // Eight live kittens on top: three under the big cat, two beside a compact one, three on a pill, each an engine that is updated and drawn.
  const kitPool = new KittenPool();
  const kit = (n: number, o = 0): Kitten[] => Array.from({ length: n }, (_, i) => ({ id: `k${o + i}`, type: "", session: null, state: (o + i) % 3 === 0 ? "searching" : "working", born: o + i, last: o + i, until: null }));
  function benchKittens(withKittens: boolean, frames: number): number {
    const c = fit(benchCv, 720, 90), t0 = performance.now();
    for (let f = 0; f < frames; f++) {
      for (const b of benchViews) drawCat(c, b.v, b.x, 45, b.d);
      if (withKittens) {
        const spot = (place: string, o: Partial<{ ox: number; oy: number; unit: number }>) => ({ place, pill: "bench", parentCat: "shrimpy", color: "#8AB4F8", ox: 400, oy: 45, unit: 20, ...o });
        drawKittens(c, kitPool, spot("bigExpanded", { ox: 640, oy: 20, unit: 66 }), kit(3), 1 / 60);
        drawKittens(c, kitPool, spot("bigCompact", { ox: 100 }), kit(2, 3), 1 / 60);
        drawKittens(c, kitPool, spot("pill", { ox: 340, unit: 28 }), kit(3, 5), 1 / 60);
        kitPool.endFrame();
      }
    }
    return (performance.now() - t0) / frames;
  }
  const measureKittens = () => {
    const none: number[] = [], eight: number[] = [];
    benchKittens(true, 20); benchKittens(false, 20); // warm up
    for (let r = 0; r < 3; r++) { none.push(benchKittens(false, 120)); eight.push(benchKittens(true, 120)); }
    const a = median(none), b = median(eight);
    benchNote.textContent = `Twelve small cats and one Ø66, with their coloured eyes: ${a.toFixed(2)} ms per frame; with eight live kittens on top (three under the big cat, two beside a compact one, three on a pill): ${b.toFixed(2)} ms (median of 3 rounds of 120 frames).`;
  };
  const benchRow = row("Frame time");
  benchRow.append(button("Measure", measure), button("Measure with 8 kittens", measureKittens));
  eyeBox.append(eyes2Wrap, eyes1Wrap, benchRow, benchNote);
  root.insertBefore(eyeBox, wrap);
  drawEyeSheet(eyes2, 2); drawEyeSheet(eyes1, 1);
  // ── Stage 3: emotes, the mouth and personality ──
  const stageBox = section("Emotes, mouth and personality", "One big cat. The six mouth values show in every state and emote. Pick a personality: it bends the motion, and Balanced changes nothing.");
  const stageCv = document.createElement("canvas");
  stageCv.id = "stage-cat";
  stageCv.style.cssText = "background:#000;border-radius:14px;display:block;margin-top:12px;cursor:pointer";
  let stage = new BotEngine(PRESETS[dev.cat]);
  let stageState: StateName = "idle";
  const remake = () => { stage = new BotEngine(PRESETS[dev.cat], { state: stageState }); };
  const emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies"];
  const emoteRow = row("Emote");
  for (const n of emotes) emoteRow.append(button(n, () => stage.emote(n)));
  emoteRow.append(button("hairball", () => stage.emote("hairball")));
  emoteRow.append(button("dance (music)", () => stage.setDancing(!stage.isDancing)));
  const persRow = choice("Personality", Object.entries(PERSONAS).map(([k, v]) => [k, v.label] as const), () => catCfg.pers[dev.cat]?.preset ?? "balanced", (v) => { catCfg.pers[dev.cat] = personaNamed(v); });
  stageBox.append(
    choice("State", STATES.map((s) => [s, s] as const), () => stageState, (v) => { stageState = v; stage.setState(v); }),
    emoteRow, persRow, stageCv,
  );
  root.insertBefore(stageBox, wrap);
  stageCv.onpointerdown = () => stage.slap();
  rebuilds.push(remake);
  const flights: { t0: number; ext: string; reject: boolean; from: { x: number; y: number } }[] = [];
  const catchRow = row("File");
  const simulate = (ext: string, reject: boolean) => {
    stage.catchOpen(true);
    setTimeout(() => { stage.catchDrop(); flights.push({ t0: performance.now(), ext, reject, from: { x: 260, y: 40 } }); }, 420);
  };
  catchRow.append(button("catch a file", () => simulate("PDF", false)), button("catch an unsupported file", () => simulate("EXE", true)));
  stageBox.insertBefore(catchRow, stageCv);
  let sLast = performance.now();
  ticks.push(() => {
    const now = performance.now(), dt = Math.min(0.05, (now - sLast) / 1000);
    sLast = now;
    const W = 300, H = 300, c = fit(stageCv, W, H), box = stageCv.getBoundingClientRect();
    stage.particleOverhang = 60;
    stage.collarColor = state.collar === "off" ? null : bigCatCollar(stageState, state.col);
    const g = gazeFrom(box.left + W / 2, box.top + H / 2 + 30);
    stage.lookX = g.x; stage.lookY = g.y;
    stage.update(dt);
    stage.draw(c, W, H);
    for (let i = flights.length - 1; i >= 0; i--) {
      const f = flights[i], k = Math.min(1, (now - f.t0) / FLIGHT_MS), m = stage.mouthAt, b = stage.base;
      if (!m || !b) continue;
      const w = flightAt(f.from, m, b.R, k);
      drawFileIcon(c, w.x, w.y, w.size, w.rot, f.ext);
      if (k >= 1) { flights.splice(i, 1); if (f.reject) stage.catchReject(f.ext); else stage.catchArrive(); }
    }
  });
  // ── Stage 4: the greeting ──
  const greetBox = section("Greeting", "The launch greeting: the cat falls in with a landing squash, bounces, slides aside, pops up for a paw wave, then slides back and settles. Move the pointer out of the page, then press Collapse, to see it cut short.");
  const gHolder = document.createElement("div");
  gHolder.style.cssText = "width:640px;max-width:100%;height:150px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin-top:12px";
  const gCv = document.createElement("canvas");
  gHolder.append(gCv);
  const dressed = { outfit: "witchhat" as string | null };
  let greeting = new Greeting();
  greeting.start(undefined, dressed.outfit);
  const gRow = row("Greeting");
  gRow.append(button("Replay", () => { greeting = new Greeting(); greeting.start(undefined, dressed.outfit); }), button("Collapse now", () => greeting.interrupt()));
  greetBox.append(choice("Outfit", ([null, "witchhat", "crown", "sunglasses", "scarf"] as const).map((o) => [o, o ?? "none"] as const), () => dressed.outfit, (v) => { dressed.outfit = v; }), gRow, gHolder);
  root.insertBefore(greetBox, wrap);
  ticks.push(() => greeting.draw(fit(gCv, 640, 150)));
  // ── Sub-project H: the desktop cat, its flight and its frame time ──
  mountDesktopDev(root, wrap, ticks);
  // ── Sub-project I: the wardrobe ──
  mountWardrobeDev(root, wrap);
  // ── Sub-project G1: the shelf, its half of the island and its badge ──
  mountShelfDev(root, wrap);
  // ── Sub-project G2: the link between your machines ──
  mountLinkDev(root, wrap);
  mountSettingsDev(root, wrap);
  mountProjectsDev(root, wrap);
  // ── Sub-project F3a-tauri: the Companion's chat samples and the Prompt box ──
  mountCompanionDev(root, wrap);

  const frame = () => {
    const t0 = performance.now();
    ticks[0]();
    const t1 = performance.now();
    for (let i = 1; i < ticks.length; i++) ticks[i]();
    sheetMs += (t1 - t0 - sheetMs) * 0.05;
    liveMs += (performance.now() - t1 - liveMs) * 0.05;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
