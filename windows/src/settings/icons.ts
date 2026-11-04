// The sidebar's page icons (Settings restyle, "The window"): the gear and the bubble from views/icons.ts, and four drawn here on the same 24 x 24 grid, filled, in white on the
// page's colour tile. Every sub-path turns the same way, so overlapping pieces fill as one shape (the non-zero rule).
import { ICONS } from "../views/icons.ts";
import type { Page } from "./route.ts";

const circle = (cx: number, cy: number, r: number): string => `M${cx - r} ${cy}a${r} ${r} 0 1 1 ${2 * r} 0a${r} ${r} 0 1 1 ${-2 * r} 0z`;

/** The icon each page shows on its tile, in the sidebar's order. */
export const PAGE_ICONS: Record<Page, string> = {
  general: ICONS.gearFill,
  // terminal.fill: a prompt and a cursor
  agents: "M4 6.2 6.1 4.4l7.1 7.6-7.1 7.6L4 17.8l5.1-5.8zM12.6 16h7.4v2h-7.4z",
  chat: ICONS.bubble,
  // puzzlepiece.extension.fill: a body with a knob on top and one on the left
  services: `M5 8h14v12H5z${circle(12, 7.4, 2.6)}${circle(4.6, 14, 2.6)}`,
  // pawprint.fill: four toes and a pad
  cat: `${circle(6.5, 10.5, 2)}${circle(10.2, 6.2, 2.2)}${circle(13.8, 6.2, 2.2)}${circle(17.5, 10.5, 2)}M12 12.2c-3.3 0-6.4 4.3-6.4 6.9 0 1.7 1.3 2.6 3 2.6 1.3 0 2.1-.6 3.4-.6s2.1.6 3.4.6c1.7 0 3-.9 3-2.6 0-2.6-3.1-6.9-6.4-6.9z`,
  // laptopcomputer: a screen and a base
  devices: "M5 4.5h14V15H5zM2.5 16h19v1.5a1.5 1.5 0 0 1-1.5 1.5H4a1.5 1.5 0 0 1-1.5-1.5z",
};
