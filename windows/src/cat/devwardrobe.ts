// The `?dev` page's "Wardrobe" panel (sub-project I): the contact sheet of all 16 outfits on all 16 coats, the compact notch's Ø20 and Ø18 big cat in their strips, the head turned a full yaw
// each way, the three neck outfits over each collar style, the desktop sizes, a Two cats pair, and Auto for any date. Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window
// needed) and compare it with the Wardrobe panel of design/prototype/notchmeow.html, which is the look. The cats are stills drawn when a control changes: the panel runs no timer and no
// frame loop. Only the dev server serves it: main.ts loads dev.ts behind `import.meta.env.DEV`, so a release build does not contain it.

import { newPose } from "./geometry.ts";
import { outfitDigest, outfitGeometry } from "./outfit.ts";
import { drawCat, stillView } from "./renderer.ts";
import { CAT_IDS, PRESETS } from "./presets.ts";
import { OUTFIT_DRAWN, OUTFIT_NAMES, resolveOutfit } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";

const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const COLLAR_COLOR = AGENT_PILL_COLORS.agent_gemini;
const CELL = 64, LEFT = 74, TOP = 34, STRIP_SCALE = 2;
/** The compact notch's strips: [head width, strip height in pt]. A 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one on a screen without a notch. */
const STRIPS: readonly (readonly [number, number])[] = [[20, 32], [18, 24]];

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
  s.id = "wardrobe-dev";
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
function scroller(cv: HTMLCanvasElement, label: string): HTMLElement {
  const w = document.createElement("div");
  w.style.cssText = "overflow-x:auto;margin-top:12px;padding-bottom:4px";
  cv.setAttribute("aria-label", label); cv.style.display = "block";
  w.append(cv);
  return w;
}
const caption = (c: CanvasRenderingContext2D, text: string, x: number, y: number, align: CanvasTextAlign = "center") => {
  c.fillStyle = B.dim; c.font = `10px ${FONT}`; c.textAlign = align; c.textBaseline = "alphabetic"; c.fillText(text, x, y);
};

/** Puts the "Wardrobe" panel into the `?dev` page before `before`. */
export function mountWardrobeDev(root: HTMLElement, before: HTMLElement): void {
  const st = { coat: "momo", turned: false, collar: "off", outfit: "witchhat" as OutfitId, date: "2025-12-24" };
  const box = section("Wardrobe", "16 outfits on 16 coats, drawn by the app's renderer from the contract's shapes (outfit.ts), to compare with the Wardrobe panel of the prototype page. Hats are as wide as the gap between the ears; the thin edge of an outfit is light on a dark coat and dark on a light one.");
  const sheet = document.createElement("canvas"), notch = document.createElement("canvas"), turned = document.createElement("canvas"), neck = document.createElement("canvas"), extra = document.createElement("canvas");
  sheet.id = "wardrobe-sheet"; notch.id = "wardrobe-notch"; turned.id = "wardrobe-turned"; neck.id = "wardrobe-neck"; extra.id = "wardrobe-extra";
  const fits = document.createElement("p");
  fits.id = "wardrobe-fits"; fits.style.cssText = `color:${B.ink};font-size:12px;margin:10px 0 0`;
  const autoOut = document.createElement("p");
  autoOut.id = "wardrobe-auto"; autoOut.style.cssText = `color:${B.ink};font-size:12px;margin:6px 0 0`;
  const date = document.createElement("input");
  date.type = "date"; date.value = st.date; date.setAttribute("aria-label", "Date for Auto"); date.style.cssText = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:3px 8px`;

  const view = (id: string, yaw = 0) => stillView(PRESETS[id], { ...newPose(), yaw, pitch: yaw ? 0.15 : 0 });
  const collar = () => (st.collar === "off" ? null : { style: st.collar, col: COLLAR_COLOR });
  const cellBg = (c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) => { c.fillStyle = "#101114"; c.beginPath(); c.roundRect(x, y, w, h, 8); c.fill(); };

  function drawSheet() {
    const c = fit(sheet, LEFT + CELL * 16, TOP + CELL * 16);
    OUTFIT_DRAWN.forEach((id, i) => OUTFIT_NAMES[id].split(" ").forEach((word, k) => caption(c, word, LEFT + CELL * i + CELL / 2, 14 + k * 10)));
    CAT_IDS.forEach((cat, r) => {
      c.fillStyle = B.ink; c.font = `600 11px ${FONT}`; c.textAlign = "left"; c.textBaseline = "middle"; c.fillText(PRESETS[cat].label, 6, TOP + CELL * r + CELL / 2);
      const v = view(cat, st.turned ? 0.6 : 0);
      OUTFIT_DRAWN.forEach((id, i) => {
        const x = LEFT + CELL * i, y = TOP + CELL * r;
        cellBg(c, x + 2, y + 2, CELL - 4, CELL - 4);
        drawCat(c, v, x + CELL / 2, y + CELL / 2 + 6, 40, { tint: false, badge: false, outfit: id, collar: collar() });
      });
    });
  }

  function drawNotch() {
    // Eight outfits to a row, two rows to a strip: the canvas is 8 cells wide, so the whole strip fits the panel's scroller instead of running off its right edge.
    const W = 56, per = W * STRIP_SCALE + 6, rowH = 32 * STRIP_SCALE + 18, PER_ROW = 8, blockH = rowH * 2 + 14;
    const c = fit(notch, per * PER_ROW, blockH * STRIPS.length);
    STRIPS.forEach(([D, h], r) => {
      OUTFIT_DRAWN.forEach((id, i) => {
        const x = (i % PER_ROW) * per, y = r * blockH + Math.floor(i / PER_ROW) * rowH;
        c.save(); c.translate(x, y + 10); c.scale(STRIP_SCALE, STRIP_SCALE);
        c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, W, h, [0, 0, 8, 8]); c.fill();
        drawCat(c, view(st.coat), W / 2, h / 2, D, { badgeSide: -1, badge: false, earCeiling: 0, outfit: id });
        c.restore();
        if (r === 0) caption(c, OUTFIT_NAMES[id], x + (W * STRIP_SCALE) / 2, y + 8);
      });
      caption(c, `Ø${D} in the ${h} pt strip, magnified ${STRIP_SCALE} times`, 4, r * blockH + 2 * rowH + 10, "left");
    });
  }

  function drawTurned() {
    const c = fit(turned, CELL * 1.5 * 16, CELL * 1.5 * 2 + 18);
    [-0.6, 0.6].forEach((yaw, r) => OUTFIT_DRAWN.forEach((id, i) => {
      const x = CELL * 1.5 * i, y = r * CELL * 1.5;
      cellBg(c, x + 2, y + 2, CELL * 1.5 - 4, CELL * 1.5 - 4);
      drawCat(c, view(st.coat, yaw), x + CELL * 0.75, y + CELL * 0.8, 52, { tint: false, badge: false, outfit: id, collar: collar() });
    }));
    caption(c, "The head turned a full yaw to the left (top row) and to the right (bottom row)", 4, CELL * 3 + 14, "left");
  }

  function drawNeck() {
    const ids: OutfitId[] = ["bell", "bandana", "scarf"], styles = ["off", "tag", "band", "kerchief"], cw = CELL * 1.5;
    const c = fit(neck, cw * styles.length * ids.length, cw + 30);
    ids.forEach((id, a) => styles.forEach((style, b) => {
      const x = cw * (a * styles.length + b);
      cellBg(c, x + 2, 2, cw - 4, cw - 4);
      drawCat(c, view(st.coat), x + cw / 2, cw * 0.55, 52, { tint: false, badge: false, outfit: id, collar: style === "off" ? null : { style, col: COLLAR_COLOR } });
      // Two lines under each cell: the outfit, then its collar (one line of both ran into the next cell's caption).
      caption(c, OUTFIT_NAMES[id], x + cw / 2, cw + 12);
      caption(c, `collar ${style}`, x + cw / 2, cw + 24);
    }));
  }

  function drawExtra() {
    const c = fit(extra, 720, 190);
    // The desktop cat's three sizes, then a Two cats pair in the compact strip (cat 1 the chosen coat, cat 2 the next one), all wearing the chosen outfit.
    // [D, x, cat y, cell height, caption y]. The Ø96 cat sits lower (y 96): its witch hat rises about 92 px above the head centre, so at y 64 it left the top of the canvas. Its cell and caption move with it.
    [[48, 70, 64, 112, 130], [64, 170, 64, 112, 130], [96, 290, 96, 140, 164]].forEach(([D, x, y, h, cap]) => {
      cellBg(c, x - 56, 4, 112, h);
      drawCat(c, view(st.coat), x, y, D * 0.9, { tint: false, badge: false, outfit: st.outfit, outfitCeiling: 0, collar: collar() });
      caption(c, `desktop Ø${D}`, x, cap);
    });
    const next = CAT_IDS[(CAT_IDS.indexOf(st.coat) + 1) % CAT_IDS.length];
    c.save(); c.translate(380, 20); c.scale(STRIP_SCALE, STRIP_SCALE);
    c.fillStyle = "#000"; c.beginPath(); c.roundRect(0, 0, 144, 32, [0, 0, 12, 12]); c.fill();
    drawCat(c, view(st.coat), 36, 16, 20, { badgeSide: -1, badge: false, earCeiling: 0, outfit: st.outfit });
    drawCat(c, view(next), 108, 16, 20, { badgeSide: -1, badge: false, earCeiling: 0, outfit: st.outfit });
    c.restore();
    caption(c, "Two cats, compact", 524, 110);
  }

  function checkFits() {
    let pairs = 0, bad = 0;
    for (const [D] of STRIPS) for (const cat of CAT_IDS) for (const id of OUTFIT_DRAWN) {
      pairs++;
      const shapes = outfitGeometry(id, PRESETS[cat], newPose(), D, { dpr: Math.min(2, devicePixelRatio || 1) });
      // An empty list has a finite box of zeros, so it is counted as broken on its own: every drawn pair has shapes.
      if (shapes.length === 0 || !outfitDigest(shapes).bbox.every(Number.isFinite)) bad++;
    }
    fits.textContent = `${pairs} outfit and coat pairs worked out for the compact strips (Ø20 in 32 pt, Ø18 in 24 pt): ${bad === 0 ? "all have shapes with finite numbers" : `${bad} are broken`}. The contract's tests check that none rises above the strip.`;
  }

  function showAuto() {
    const [y, m, d] = date.value.split("-").map(Number);
    const out = resolveOutfit("auto", y, m, d);
    autoOut.textContent = `Auto on ${date.value || "(no date)"}: ${out === "none" ? "no outfit" : OUTFIT_NAMES[out]}`;
  }

  const redraw = () => { drawSheet(); drawNotch(); drawTurned(); drawNeck(); drawExtra(); showAuto(); };
  date.onchange = () => { showAuto(); };
  box.append(
    choice("Coat", CAT_IDS.map((c) => [c, PRESETS[c].label] as const), () => st.coat, (v) => { st.coat = v; redraw(); }),
    choice("Head", [[false, "Facing"], [true, "Turned (the sheet)"]] as const, () => st.turned, (v) => { st.turned = v; redraw(); }),
    choice("Collar", ([["off", "Off"], ["tag", "Band and tag"], ["band", "Band"], ["kerchief", "Neckerchief"]] as const), () => st.collar, (v) => { st.collar = v; redraw(); }),
    choice("Outfit", OUTFIT_DRAWN.map((id) => [id, OUTFIT_NAMES[id]] as const), () => st.outfit, (v) => { st.outfit = v; redraw(); }),
    scroller(sheet, "Every outfit on every coat"),
    scroller(notch, "Every outfit on the compact notch's big cat"),
    scroller(turned, "Every outfit with the head turned each way"),
    scroller(neck, "The bell, bandana and scarf over each collar style"),
    scroller(extra, "The chosen outfit at the desktop sizes and on a Two cats pair"),
    fits,
  );
  const ar = row("Auto");
  ar.append(date);
  box.append(ar, autoOut);
  root.insertBefore(box, before);
  redraw();
  checkFits();
}
