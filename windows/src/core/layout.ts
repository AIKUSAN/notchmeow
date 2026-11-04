// Island geometry — ported from IslandTypes.swift + IslandWindowController.islandSize
// + IslandRootView.botPosition. All values are logical pixels, identical to the
// macOS app's points.

import { THEME } from "../theme.generated.ts";

export type IslandMode = "hidden" | "compact" | "expanded";

export type IslandViewName =
  | "overview"
  | "empty"
  | "approval"
  | "question"
  | "error"
  | "finished"
  | "confused"
  | "upload"
  | "uploading"
  | "choose"
  | "mail"
  | "prompt"
  | "searching"
  | "result"
  | "note"
  | "settings"
  | "greeting"
  | "sidekick"
  | "projects"
  | "shelf"
  | "link";

export type BotStateName =
  | "idle"
  | "working"
  | "thinking"
  | "searching"
  | "approval"
  | "question"
  | "error"
  | "finished"
  | "ratelimit"
  | "sleeping"
  | "dizzy";

export type BotEmoteName = "love" | "surprised" | "proud" | "wink" | "yawn" | "happy" | "annoyed";

export type AgentLayoutMode = "none" | "grid" | "pills" | "column";

export interface ViewLayout {
  height: number;
  botX: number;
  botY: number | null; // null = auto-centred
  botDiameter: number;
  agentMode: AgentLayoutMode;
}

// The window is a fixed 720×600 (the chat at 560 px with the corner under it); the island is
// drawn inside it, glued to the top edge and horizontally centred. The window is transparent and
// never the hit area: the island's own rect decides what takes the mouse (island.rs, `takes_mouse`
// and `click_region`). Its twin is `PANEL_H` in src-tauri/src/island.rs; size.test.mjs holds them equal.
export const PANEL_W = 720;
export const PANEL_H = 600;

// No notch on a PC: these are the hidden/compact sizes from docs/SPEC.md.
export const NOTCH_W = 184;
export const NOTCH_H = 32;
export const COMPACT_W = 288; // NOTCH_W + 104
export const EXPANDED_W = 640;

export const ROUNDED_CORNER = 14; // hidden / compact
export const EXPANDED_CORNER = 22;

/** Invisible hover strip that wakes the island when hidden. */
export const WAKE_STRIP_W = 240;
export const WAKE_STRIP_H = 6;

export const VIEW_LAYOUTS: Record<IslandViewName, ViewLayout> = {
  overview: { height: 160, botX: 68, botY: null, botDiameter: 58, agentMode: "pills" },
  empty: { height: 160, botX: 70, botY: null, botDiameter: 62, agentMode: "none" },
  approval: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
  question: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
  error: { height: 160, botX: 62, botY: null, botDiameter: 58, agentMode: "column" },
  finished: { height: 160, botX: 62, botY: null, botDiameter: 58, agentMode: "column" },
  confused: { height: 160, botX: 76, botY: null, botDiameter: 66, agentMode: "column" },
  upload: { height: 176, botX: 140, botY: 104, botDiameter: 62, agentMode: "column" },
  // botY 103 = bar top (42 + 58) + 3, so the dot really rides the bar. The Swift
  // layout says 118 while its own comment says 103; the comment matches the spec.
  uploading: { height: 176, botX: 46, botY: 103, botDiameter: 20, agentMode: "none" },
  choose: { height: 176, botX: 60, botY: 101, botDiameter: 52, agentMode: "column" },
  mail: { height: 240, botX: 56, botY: null, botDiameter: 46, agentMode: "column" },
  prompt: { height: 160, botX: 52, botY: null, botDiameter: 44, agentMode: "column" },
  searching: { height: 160, botX: 52, botY: null, botDiameter: 44, agentMode: "column" },
  result: { height: 160, botX: 52, botY: null, botDiameter: 44, agentMode: "column" },
  note: { height: 160, botX: 60, botY: null, botDiameter: 50, agentMode: "column" },
  settings: { height: 160, botX: 54, botY: null, botDiameter: 46, agentMode: "none" },
  // The shelf (sub-project G1): the cat small at the left, the tray's tiles to its right.
  shelf: { height: 176, botX: 46, botY: 108, botDiameter: 44, agentMode: "none" },
  greeting: { height: 150, botX: 320, botY: 90, botDiameter: 0, agentMode: "none" },
  // The link's card (sub-project G2): a pairing code, an offer from another machine, a file coming in, the end of any of them. Laid out as the approval card is.
  link: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
  // The Projects screen (sub-project P): the cat small at the left (its head ends at x 68), the list from x 90 (views/projects.ts, projects/projects.css).
  projects: { height: 240, botX: 46, botY: null, botDiameter: 44, agentMode: "none" },
  // The Sidekick's note (sub-project F1): a recap or a nudge, laid out as a finished task's card. Its height grows with its lines (`sidekickHeight`).
  sidekick: { height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" },
};

// The upload views above are only the fallback geometry. Once a file is actually
// dropped the whole sequence — the cat included — is drawn by src/upload, which
// owns its own constants (USC) straight from UploadSequenceEngine.swift.

/** Chat view grows with the conversation — the Mac's ChatSizing: 240 px empty, 40 px a message, 560 at most. */
export function chatPromptHeight(messageCount: number): number {
  return Math.min(560, 240 + messageCount * 40);
}

/** The Sidekick's view grows by one more line of text per line of the note, up to a recap's three lines and "+N more". */
export function sidekickHeight(lines: number): number {
  return Math.min(280, 160 + 30 * Math.max(0, Math.floor(lines) - 1));
}

export function islandSize(
  mode: IslandMode,
  view: IslandViewName,
  chatCount = 0,
  noteLines = 1,
  overviewExtra = 0,
): { w: number; h: number } {
  switch (mode) {
    case "hidden":
      // No notch to hide inside on a PC: the island retracts to zero height and
      // slides into the top edge of the screen instead of sitting there as a bar.
      return { w: NOTCH_W, h: 0 };
    case "compact":
      return { w: COMPACT_W, h: NOTCH_H };
    case "expanded": {
      // The overview grows by the Projects section's height (overviewExtra); no other view does.
      const h = view === "prompt" ? chatPromptHeight(chatCount) : view === "sidekick" ? sidekickHeight(noteLines) : VIEW_LAYOUTS[view].height + (view === "overview" ? overviewExtra : 0);
      return { w: EXPANDED_W, h };
    }
  }
}

export interface BotPlacement {
  cx: number;
  cy: number;
  diameter: number;
  opacity: number;
}

/** IslandRootView.botPosition — cy is measured from the island's top edge. */
export function botPosition(
  mode: IslandMode,
  view: IslandViewName,
  islandH: number,
  uploadProgress = 0,
): BotPlacement {
  switch (mode) {
    case "hidden":
      return { cx: 46, cy: 16, diameter: 6, opacity: 0 };
    case "compact":
      return { cx: 40, cy: 16, diameter: 20, opacity: 1 };
    case "expanded": {
      const layout = VIEW_LAYOUTS[view];
      if (view === "uploading") {
        return {
          cx: 36 + uploadProgress * 526,
          cy: layout.botY ?? 103,
          diameter: layout.botDiameter,
          opacity: 1,
        };
      }
      if (layout.botY != null) {
        return { cx: layout.botX, cy: layout.botY, diameter: layout.botDiameter, opacity: 1 };
      }
      // Centre of the fixed 84 pt card (8 pt top inset + 34 pt header → content at y = 42). The overview's section opens below the cards: the big cat keeps the
      // overview's own height (the Mac's guard), so it does not move down when the section opens.
      const headerBottom = 42;
      const cardH = 84;
      const h = view === "overview" ? Math.min(islandH, VIEW_LAYOUTS.overview.height) : islandH;
      const cy = headerBottom + (h - headerBottom - cardH) / 2 + cardH / 2;
      return { cx: layout.botX, cy, diameter: layout.botDiameter, opacity: 1 };
    }
  }
}

/**
 * Two cats mode (spec §2): where the pair sits, in px from the island's left edge, and the cats' head widths. Compact: two Ø20 cats share the left ear, at 30 and 54.
 * Expanded, in the overview: cat 1 at Ø58 and cat 2 at Ø46 side by side with a 6 px gap between the heads (the owner made room at B-0's checkpoint: cat 2 at 114), 3 px above
 * and 5 px below the card's middle. The numbers are the prototype's mock-up
 * (design/prototype/notchmeow.html, `drawDesk`), a reference and not part of the contract.
 */
export const PAIR = {
  compact: { d: 20, x1: 30, x2: 54 },
  expanded: { d1: 58, x1: 56, dy1: -3, d2: 46, x2: 114, dy2: 5 },
} as const;

/**
 * The two cats of Two cats mode: compact, or expanded in the overview (every other view keeps its one cat where it is, so the cards' text is never covered). Null when the
 * island is hidden or the view is not the overview. `islandH` is the island's height now.
 */
export function pairPlacement(mode: IslandMode, view: IslandViewName, islandH: number): { first: BotPlacement; second: BotPlacement } | null {
  if (mode === "compact") {
    const c = PAIR.compact;
    return { first: { cx: c.x1, cy: 16, diameter: c.d, opacity: 1 }, second: { cx: c.x2, cy: 16, diameter: c.d, opacity: 1 } };
  }
  if (mode !== "expanded" || view !== "overview") return null;
  const e = PAIR.expanded, cy = botPosition(mode, view, islandH).cy;
  return { first: { cx: e.x1, cy: cy + e.dy1, diameter: e.d1, opacity: 1 }, second: { cx: e.x2, cy: cy + e.dy2, diameter: e.d2, opacity: 1 } };
}

export function botGlowColor(s: BotStateName): string {
  switch (s) {
    case "working":
      return THEME.state.glow.working;
    case "thinking":
      return THEME.state.glow.thinking;
    case "searching":
      return THEME.state.glow.searching;
    case "approval":
      return THEME.state.glow.approval;
    case "error":
      return THEME.state.glow.error;
    case "finished":
      return THEME.state.glow.finished;
    case "ratelimit":
      return THEME.state.glow.ratelimit;
    default:
      return "#FFFFFF";
  }
}

export function botGlowOpacity(s: BotStateName): number {
  switch (s) {
    case "idle":
    case "sleeping":
      return 0.15;
    case "dizzy":
      return 0;
    default:
      return 0.65;
  }
}

// Project colours (IslandConst.projectColors)
const PROJECT_COLORS: Record<string, string> = {};

const FALLBACK_COLORS = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"];

export function colorForProject(name: string): string {
  const key = name.toLowerCase().trim();
  const exact = PROJECT_COLORS[key];
  if (exact) return exact;
  for (const [k, c] of Object.entries(PROJECT_COLORS)) {
    if (key.startsWith(k) || key.includes(k)) return c;
  }
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0;
  return FALLBACK_COLORS[Math.abs(hash) % FALLBACK_COLORS.length];
}

// Card wash colours (CardBackground.washColor)
export type Wash = "red" | "green" | "pink" | "amber" | "cyan" | "indigo" | "soft" | null;

export function washRGBA(wash: Wash): string {
  switch (wash) {
    case "red":
      return "rgba(244,80,94,0.55)";
    case "green":
      return "rgba(52,211,153,0.5)";
    case "pink":
      return "rgba(244,114,182,0.55)";
    case "amber":
      return "rgba(245,165,36,0.42)";
    case "cyan":
      return "rgba(34,211,238,0.38)";
    case "indigo":
      return "rgba(99,102,241,0.5)";
    case "soft":
      return "rgba(255,255,255,0.08)";
    default:
      return "rgba(0,0,0,0)";
  }
}

export interface Circle { cx: number; cy: number; r: number }

/** Which cat a click on the big cat's row hits: 1, 2 or 0 (neither). Where the two circles overlap, the cat whose centre is nearer the click wins (a tie goes to cat 1). */
export function catClickTarget(x: number, y: number, c1: Circle, c2: Circle | null): 0 | 1 | 2 {
  const d = (c: Circle) => (x - c.cx) ** 2 + (y - c.cy) ** 2;
  const in1 = d(c1) <= c1.r * c1.r, in2 = c2 !== null && d(c2) <= c2.r * c2.r;
  return in1 && in2 ? (d(c2) < d(c1) ? 2 : 1) : in2 ? 2 : in1 ? 1 : 0;
}

/** Whether a press is on the big cat: the cat the press hits is cat 1. In Two cats mode (`c2` given) a press in cat 2's part of the overlap is cat 2's, so it drags nothing out of the notch. */
export function bigCatPressed(x: number, y: number, c1: Circle, c2: Circle | null): boolean {
  return catClickTarget(x, y, c1, c2) === 1;
}
