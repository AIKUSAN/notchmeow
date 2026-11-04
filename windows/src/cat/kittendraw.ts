// Drawing subagent kittens (sub-project B, spec §3). `kittenSlots` (kittens.ts, the contract) says where each kitten sits beside its parent, in multiples of a unit; this
// draws them: each is a live engine of `kittenOf(the parent's coat)`, with the parent's motion, personality and collar (in the parent's colour, in the style that coat
// wears), its own state badge, and a happy blink while it leaves. The "+N" of a row that is too long and the "×N" count by a pair are small labels. No timer and no loop of
// its own: the island's frame loop calls `drawKittens` for each parent, and an engine nobody has drawn for a while is dropped.
// Imports engine.ts, kittens.ts and presets.ts, so the plain-Node checks (npm run check:cat) can load it.

import { BotEngine } from "./engine.ts";
import { kittenSlots } from "./kittens.ts";
import type { Kitten, KittenSlots } from "./kittens.ts";
import { catById, kittenOf } from "./presets.ts";
import type { StateName } from "./base.ts";

/** The state a kitten shows: its own (working, searching, waiting on an approval), and the finished look, a happy blink, while it leaves. */
export const kittenCatState = (state: string): StateName => (state === "leaving" ? "finished" : state === "approval" ? "approval" : state === "searching" ? "searching" : "working");

/** Frames an engine may go undrawn before it is dropped: a kitten that left, or a parent that is not on screen. */
const KEEP_FRAMES = 30;

/** The engines of the kittens on screen, made when a kitten is first drawn and kept while it is. One pool per page. */
export class KittenPool {
  private readonly engines = new Map<string, { e: BotEngine; used: number }>();
  private frame = 0;

  /** The engine of this kitten, as a kitten of `parentCat`: made once per (key, parent coat), and put in `state`. */
  get(key: string, parentCat: string, state: StateName): BotEngine {
    const k = `${key}:${parentCat}`;
    let slot = this.engines.get(k);
    if (!slot) {
      slot = { e: new BotEngine(kittenOf(catById(parentCat)), { mini: true, state }), used: this.frame };
      this.engines.set(k, slot);
    }
    slot.used = this.frame;
    slot.e.setState(state);
    return slot.e;
  }

  /** Ends a frame: an engine that has not been drawn for a while goes. */
  endFrame() {
    this.frame++;
    for (const [k, slot] of this.engines) if (this.frame - slot.used > KEEP_FRAMES) this.engines.delete(k);
  }

  get size(): number { return this.engines.size; }
}

/** Where one parent's kittens go: the place (kittens.ts `KITTEN_PLACES`), the parent's pill and coat, its collar colour (null for none), and the parent's centre (or, for a pill, its trailing edge and middle) and unit in px. */
export interface KittenSpot { place: string; pill: string; parentCat: string; color: string | null; ox: number; oy: number; unit: number }

/** A small rounded label ("+3", "×4") `size` px high, centred on (x, y), or, with `left`, its left edge at x. */
function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number, left = false) {
  const sz = Math.max(8, size);
  ctx.font = `700 ${sz}px system-ui, "Segoe UI", sans-serif`;
  const w = ctx.measureText(text).width + sz * 0.6, x0 = left ? x : x - w / 2;
  ctx.fillStyle = "#2a2c31"; ctx.beginPath(); ctx.roundRect(x0, y - sz * 0.65, w, sz * 1.3, sz * 0.65); ctx.fill();
  ctx.fillStyle = "#cfd0d4"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(text, x0 + w / 2, y + 0.5);
}

/** Where a kitten's state badge ends on its right, in heads from the kitten's centre: the "+N" of a row starts there. */
export const BADGE_RIGHT = 0.85;
/** The places whose "+N" sits in the row, right of the last kitten: its left edge clears that kitten's state badge (`BADGE_RIGHT`), and under the pair it is on the row's line, so it stays inside the card. */
const IN_ROW = new Set(["bigExpanded", "pairExpanded"]);

/**
 * Draws one parent's kittens (`kittens` is `kittenView`'s list) at `spot`, `dt` seconds after the last frame, and returns the slots it used. Each kitten is a head of width
 * `d * unit` at `(ox, oy) + (x, y) * unit`; the "+N" and the "×N" are labels at their own places. Nothing is drawn for an empty list or an unknown place.
 */
export function drawKittens(ctx: CanvasRenderingContext2D, pool: KittenPool, spot: KittenSpot, kittens: readonly Kitten[], dt: number): KittenSlots {
  const slots = kittenSlots(spot.place, kittens);
  for (const q of slots.shown) {
    const e = pool.get(`${spot.place}:${spot.pill}:${q.id}`, spot.parentCat, kittenCatState(q.state)), head = q.d * spot.unit, w = head / 0.6;
    e.collarColor = spot.color;
    e.update(dt);
    ctx.save(); ctx.translate(spot.ox + q.x * spot.unit - w / 2, spot.oy + q.y * spot.unit - w / 2); e.draw(ctx, w, w); ctx.restore();
  }
  ctx.save();
  const last = slots.shown[slots.shown.length - 1];
  if (slots.moreAt && last && IN_ROW.has(spot.place)) label(ctx, `+${slots.more}`, spot.ox + (last.x + last.d * BADGE_RIGHT) * spot.unit, spot.oy + last.y * spot.unit, slots.moreAt.size * spot.unit, true);
  else if (slots.moreAt) label(ctx, `+${slots.more}`, spot.ox + slots.moreAt.x * spot.unit, spot.oy + slots.moreAt.y * spot.unit, slots.moreAt.size * spot.unit);
  if (slots.label) label(ctx, slots.label.text, spot.ox + slots.label.x * spot.unit, spot.oy + slots.label.y * spot.unit, slots.label.size * spot.unit);
  ctx.restore();
  return slots;
}
