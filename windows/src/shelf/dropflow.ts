// Which half a drop landed in, and what it does (sub-project G1). Pure, so the plain-Node checks load it.
//
// The drop event carries the paths, and the pointer's position in the webview's physical pixels. Windows has a global cursor (the island's own poll), which keeps the position
// the drop sequence already follows; Linux/Wayland has none, so the event's own position is the pointer. One rule turns either into the contract's `zoneAt(x, width)`.

import { zoneAt, type Zone } from "./rules.ts";

export interface PointerInput {
  /** The OS has a global cursor (Windows): `polledX` is the pointer. Otherwise the drag event's own `position` is. */
  cursorPoll: boolean;
  /** The pointer's x from the island's left edge, as the cursor poll last reported it (CSS px). */
  polledX: number;
  /** The drag event's position in the webview's physical pixels, when it had one. */
  position?: { x: number; y: number } | null;
  /** CSS px to physical px (the page's `devicePixelRatio`). */
  scale: number;
  /** The island's left edge in the window (CSS px). */
  islandX: number;
}

/** The pointer's x from the island's left edge, in CSS px. */
export function pointerX(i: PointerInput): number {
  if (!i.cursorPoll && i.position && i.scale > 0) return i.position.x / i.scale - i.islandX;
  return i.polledX;
}

/** The contract's rule on the pointer: "ask", "shelf", or null outside the island. */
export function dropZone(i: PointerInput, islandWidth: number): Zone | null {
  return zoneAt(pointerX(i), islandWidth);
}

export type DropPlan = { kind: "ask"; path: string } | { kind: "shelf"; paths: string[] } | { kind: "none" };

/** What a drop does. Ask takes the first file only, as it always has. Shelf takes them all. A drop outside both halves is Ask's, the drop that exists today. */
export function planDrop(zone: Zone | null, paths: readonly string[] | undefined): DropPlan {
  if (!paths?.[0]) return { kind: "none" };
  return zone === "shelf" ? { kind: "shelf", paths: [...paths] } : { kind: "ask", path: paths[0] };
}
