// Painting an outfit (sub-project I). outfit.ts says where the shapes go and what they are (head-local px, colour roles); this only paints them into a 2D context that is already in
// the head's own frame (the renderer's `inHead`), one slot at a time, and resolves the roles through the theme (`THEME.outfits`, shared/theme.json). It never reads a coat. Imports
// outfit.ts, wardrobe.ts and the generated theme, so the plain-Node checks (npm run check:cat) can load it.

import { TAU } from "./base.ts";
import { outfitAnchors, outfitGeometry, outfitRoom } from "./outfit.ts";
import type { OutfitOptions, OutfitShape, OutfitSlot } from "./outfit.ts";
import { OUTFIT_DRAWN } from "./wardrobe.ts";
import type { CatPreset, Pose } from "./types.ts";
import { THEME } from "../theme.generated.ts";

type Ctx = CanvasRenderingContext2D;

/** Every colour role an outfit uses, as "#RRGGBB": the keys of the theme's `outfits` group. */
const ROLES: Readonly<Record<string, string>> = THEME.outfits;

/** The colour of a role: the thin `edge` is light on a dark head and dark on a light one; a role the theme does not have is the dark edge (the tests prove there is none). */
export function outfitColor(role: string, edge: "light" | "dark"): string {
  if (role === "edge") return edge === "light" ? THEME.outfits.edgeLight : THEME.outfits.edgeDark;
  return Object.prototype.hasOwnProperty.call(ROLES, role) ? ROLES[role] : THEME.outfits.edgeDark;
}

/**
 * The shapes of the outfit one cat wears this frame, or null for none. `headY` is the head's y and `ceiling` the y of the top of the strip it sits in (the compact island passes it, as it
 * does for the ears): a hat is shortened to the room between them. Anything that is not one of the 16 drawn outfits is null, and nothing is computed for it.
 */
export function outfitShapes(id: unknown, p: CatPreset, s: Pose, D: number, headY: number, ceiling: number | undefined, o: OutfitOptions): OutfitShape[] | null {
  if (typeof id !== "string" || !(OUTFIT_DRAWN as readonly string[]).includes(id)) return null;
  const room = ceiling === undefined ? null : outfitRoom(outfitAnchors(p, s, D, o), headY, ceiling);
  const shapes = outfitGeometry(id, p, s, D, { ...o, room });
  return shapes.length ? shapes : null;
}

/** Paints the shapes of one slot, in order. The context is in the head's frame; its state is saved and restored. */
export function paintOutfit(c: Ctx, shapes: readonly OutfitShape[], slot: OutfitSlot, edge: "light" | "dark"): void {
  if (!shapes.some((sh) => sh.slot === slot)) return;
  c.save();
  c.lineCap = "round";
  c.lineJoin = "round";
  for (const sh of shapes) {
    if (sh.slot !== slot) continue;
    c.globalAlpha = sh.a;
    c.beginPath();
    if (sh.k === "ellipse") c.ellipse(sh.x, sh.y, sh.rx, sh.ry, sh.rot, 0, TAU);
    else {
      sh.pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y)));
      if (sh.k === "poly") c.closePath();
    }
    if (sh.k !== "curve" && sh.fill) {
      c.fillStyle = outfitColor(sh.fill, edge);
      c.fill();
    }
    if (sh.stroke && sh.sw > 0) {
      c.strokeStyle = outfitColor(sh.stroke, edge);
      c.lineWidth = sh.sw;
      c.stroke();
    }
  }
  c.restore();
}
