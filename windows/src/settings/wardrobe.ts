// Settings → Wardrobe (sub-project I): dress the big cats. A live preview of the Main cat (or any coat you pick, which changes nothing) wearing the tile under the pointer, else the chosen outfit,
// and the grid of 18 tiles in the contract's order: Auto and None, then Seasonal, Everyday, Cat extras and The cats' own. A click stores the tile's ID. Built from the window's own styles
// (.cat-grid's cells, .row, select, .hint); the new rules in settings.css are new class names only. The preview draws only while the window can be seen: the Cat section's one loop
// (cat/loop.ts) calls `draw`, the tiles are stills redrawn when something they show changes, and nothing here runs a timer or a loop of its own.

import { BotEngine } from "../cat/engine";
import { newPose } from "../cat/geometry";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { drawCat, stillView } from "../cat/renderer";
import { cleanCatBlock, withOutfit } from "../cat/display";
import type { CatBlock } from "../cat/display";
import { localDate, previewOutfit, storedFor, wardrobeTiles } from "../cat/wardrobeui";
import type { OutfitId } from "../cat/wardrobe";
import { h } from "../views/dom";
import { card, setValue } from "./kit.ts";
import type { UiKit } from "./display";

/** What the section needs from the Cat section: the `cat` block as it is now, and a place to put the new one. */
export interface WardrobeHost {
  block(): CatBlock;
  put(next: CatBlock, final: boolean): void;
}

const TILE = 48;
const PREVIEW_W = 140;
const PREVIEW_H = 150;
/** The preview's collar colour: no agent is driving it, so it wears a sample, to show how the neck outfits sit over the collar style chosen in the Cat section. */
const SAMPLE_COLLAR = "#F29B38";

export function wardrobeSection(host: WardrobeHost, ui: UiKit) {
  const now = (): CatBlock => cleanCatBlock(host.block());
  let hover: OutfitId | null = null;
  // The coat the preview and the tiles show. It starts as the Main cat and is never stored: picking another only changes what you see here.
  let coat = now().character;

  const tiles = new Map<OutfitId, { btn: HTMLButtonElement; cv: HTMLCanvasElement; text: HTMLElement }>();
  const groups = wardrobeTiles(localDate(new Date())).map((g) => {
    const grid = h("div", { class: "wardrobe-grid", role: "group", "aria-label": g.name || "Choices" });
    for (const t of g.tiles) {
      const cv = h("canvas", {});
      ui.sized(cv, TILE, TILE);
      const text = h("span", { text: t.label });
      const btn = h("button", { class: `cat-cell wardrobe-cell${t.wide ? " wide" : ""}`, "aria-pressed": "false", title: t.label, onclick: () => host.put(withOutfit(now(), storedFor(t.id)), true) }, cv, text);
      btn.addEventListener("mouseenter", () => { hover = t.id; });
      btn.addEventListener("mouseleave", () => { hover = null; });
      btn.addEventListener("focus", () => { hover = t.id; });
      btn.addEventListener("blur", () => { hover = null; });
      tiles.set(t.id, { btn, cv, text });
      grid.append(btn);
    }
    return { name: g.name, grid };
  });

  const previewCv = h("canvas", {});
  ui.sized(previewCv, PREVIEW_W, PREVIEW_H);
  const preview = new BotEngine(PRESETS[coat]);
  preview.particleOverhang = 40;
  preview.collarColor = SAMPLE_COLLAR;

  const picker = ui.menu(CAT_IDS.map((id) => [id, PRESETS[id].label] as const), (v) => { coat = v; preview.setCoat(coat); drawTiles(); });
  const pickerRow = ui.row("Preview on", picker, h("span", { class: "hint", text: "Only the preview: nothing is stored." }));
  const chosen = h("div", { class: "hint" });

  /** The tiles are stills of the preview's coat wearing what each tile stands for. */
  function drawTiles() {
    const on = localDate(new Date()), view = stillView(PRESETS[coat], newPose()), dpr = Math.min(2, window.devicePixelRatio || 1);
    for (const g of wardrobeTiles(on)) for (const t of g.tiles) {
      const e = tiles.get(t.id);
      const ctx = e?.cv.getContext("2d");
      if (!e || !ctx) continue;
      e.text.textContent = t.label;
      e.btn.title = t.label;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, TILE, TILE);
      drawCat(ctx, view, TILE / 2, TILE / 2 + 8, 26, { tint: false, badge: false, outfit: t.wears === "none" ? null : t.wears, dpr });
    }
  }

  /** Follows the stored block: the pressed tile, the chosen line and the stills (Auto's tile shows today). */
  function sync() {
    const b = now(), on = localDate(new Date());
    for (const [id, e] of tiles) e.btn.setAttribute("aria-pressed", String(id === b.outfit));
    const name = [...wardrobeTiles(on).flatMap((g) => g.tiles)].find((t) => t.id === b.outfit)?.label ?? "";
    chosen.textContent = `Worn by every big cat: ${name}. The small cats and the kittens stay bare.`;
    setValue(picker, coat);
    drawTiles();
  }

  /** One frame of the preview, `dt` seconds after the last (the Cat section's loop calls it only while the window can be seen and has focus). */
  function draw(dt: number) {
    const ctx = previewCv.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    preview.outfit = previewOutfit(now().outfit, hover, localDate(new Date()));
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, PREVIEW_W, PREVIEW_H);
    preview.update(dt);
    preview.draw(ctx, PREVIEW_W, PREVIEW_H);
  }

  const el = card("Wardrobe", null,
    h("div", { class: "hint", text: "Dress your big cats: one outfit at a time, or let Auto pick for the season. It fits every coat. Point at a tile to try it on." }),
    h("div", { class: "cat-top" }, h("div", { class: "wardrobe-tiles" },
      ...groups.flatMap((g) => [...(g.name ? [h("div", { class: "hint", text: g.name })] : []), g.grid])), h("div", { class: "cat-preview" }, previewCv)),
    pickerRow,
    chosen,
  );
  sync();
  return { el, sync, draw };
}
