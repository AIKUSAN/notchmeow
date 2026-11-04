// Drawing the desktop cat (sub-project H, spec §2): the big cat at full detail by the same renderer as the notch's, its collar, its state badge (the engine draws it) and up to three
// of its agent's kittens at the lower right (or left), then "+N". No small eyes: the cat is far above Ø28. The window's layout (desktopview.ts) says where everything goes; this
// draws one frame into a canvas the caller has cleared and given the DPR transform. Imports engine.ts and kittendraw.ts, so the plain-Node checks (npm run check:cat) can load it.

import type { BotEngine } from "./engine.ts";
import { desktopKittenSlots } from "./desktop.ts";
import type { DesktopWindowLayout } from "./desktopview.ts";
import { KittenPool, kittenCatState } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";

/** What the desktop cat shows: the coat the big cat wears now, its collar colour (null for none), its agent's kittens as `kittenView` returned them, where it looks (-1..1) and whether it dances. */
export interface DesktopLook {
  coat: string; collar: string | null; kittens: readonly Kitten[]; lookX: number; lookY: number; dancing: boolean;
  /** The agent pill the kittens belong to (their engines are kept per pill). */
  pill: string;
  /** The outfit the cat wears (a resolved ID, or none/null for none). Only the cat: its kittens stay bare. */
  outfit?: string | null;
}

/** A small rounded label ("+3") `size` px high, its left edge at `x`, centred on `y`. */
function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number) {
  const sz = Math.max(8, size);
  ctx.font = `700 ${sz}px system-ui, "Segoe UI", sans-serif`;
  const w = ctx.measureText(text).width + sz * 0.6;
  ctx.fillStyle = "#2a2c31"; ctx.beginPath(); ctx.roundRect(x, y - sz * 0.65, w, sz * 1.3, sz * 0.65); ctx.fill();
  ctx.fillStyle = "#cfd0d4"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(text, x + w / 2, y + 0.5);
}

/** Draws one frame, `dt` seconds after the last: updates and draws the cat, then its kittens. Returns nothing; the caller owns the canvas. */
export function drawDesktopCat(ctx: CanvasRenderingContext2D, engine: BotEngine, pool: KittenPool, lay: DesktopWindowLayout, look: DesktopLook, dt: number): void {
  engine.setCoat(look.coat);
  engine.collarColor = look.collar;
  engine.outfit = look.outfit ?? null;
  engine.particleOverhang = lay.overhang;
  engine.badgeLeft = false;
  engine.earRoom = null;
  // The window's top is the canvas's top: a hat is shortened to the room under it (the contract's outfitRoom), the ears are not fitted (earRoom is null above).
  engine.outfitCeiling = 0;
  engine.setDancing(look.dancing);
  engine.lookX = look.lookX;
  engine.lookY = look.lookY;
  engine.update(dt);
  ctx.save();
  ctx.translate(lay.canvasX, 0);
  engine.draw(ctx, lay.canvasW, lay.canvasH);
  ctx.restore();

  const slots = desktopKittenSlots(look.kittens, lay.side), D = lay.D;
  for (const q of slots.shown) {
    const e = pool.get(`desktop:${look.pill}:${q.id}`, look.coat, kittenCatState(q.state)), w = (q.d * D) / 0.6;
    e.collarColor = look.collar;
    e.update(dt);
    ctx.save();
    ctx.translate(lay.headX + q.x * D - w / 2, lay.headY + q.y * D - w / 2);
    e.draw(ctx, w, w);
    ctx.restore();
  }
  if (slots.moreAt) {
    ctx.save();
    const size = slots.moreAt.size * D, x = lay.headX + slots.moreAt.x * D;
    label(ctx, `+${slots.more}`, lay.side === 1 ? x : x - size * 2.2, lay.headY + slots.moreAt.y * D, size);
    ctx.restore();
  }
  pool.endFrame();
}
