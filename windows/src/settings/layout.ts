// The Settings window's sizes and the rules that turn the window's width into a sidebar and a column (the Settings restyle spec, "What is left to the builder"). Port of
// NotchBuddy/Sources/App/SettingsLayout.swift: the numbers are the same, and drift.test.mjs reads the Swift file to hold them equal. Pure: no DOM, no clock.

export type SidebarMode = "expanded" | "icons";

export const MIN_W = 415, MIN_H = 420, DEFAULT_W = 720, DEFAULT_H = 560, BREAKPOINT = 600, SIDEBAR_WIDE = 200, SIDEBAR_ICONS = 56,
  COLUMN_MAX = 640, PADDING = 20, PADDING_COLLAPSED = 16, FIELD_MAX = 420, NUMBER_FIELD = 64, PICKER_WIDTH = 180, HELP_SIZE = 12, TAB_BAR_HEIGHT = 28;

/** "Close after": 5 to 120 seconds; 15 when the field holds no number (an empty field, a word, or 0). */
export function closeAfter(v: string): number {
  return Math.max(5, Math.min(120, Number(v) || 15));
}

/** Icons under the breakpoint (600 px), the wide sidebar at or above it. */
export function sidebarMode(windowWidth: number): SidebarMode {
  return windowWidth < BREAKPOINT ? "icons" : "expanded";
}

/** The content column: the window less the sidebar and the side padding on both sides, at most COLUMN_MAX, never negative. */
export function columnWidth(windowWidth: number): number {
  const mode = sidebarMode(windowWidth);
  const sidebar = mode === "icons" ? SIDEBAR_ICONS : SIDEBAR_WIDE;
  const padding = mode === "icons" ? PADDING_COLLAPSED : PADDING;
  return Math.max(0, Math.min(windowWidth - sidebar - 2 * padding, COLUMN_MAX));
}

const WINDOWS_HOME = /^[A-Za-z]:\\/;
const escapeRegExp = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** A path with the home folder shown as `~`. A Windows home (`C:\...`) compares case-insensitively, a POSIX home exactly; a path under the home with either separator
 * becomes `~` plus the rest as written. Anything else, a path outside the home included, is unchanged. */
export function displayPath(path: string, home: string): string {
  if (!home) return path;
  // One normaliser for both comparisons: lower case on a Windows home, the text as it is on a POSIX one.
  const fold = (s: string): string => (WINDOWS_HOME.test(home) ? s.toLowerCase() : s);
  const h = fold(home), p = fold(path);
  if (p === h) return "~";
  if (p.startsWith(h + "\\") || p.startsWith(h + "/")) return "~" + path.slice(home.length);
  return path;
}

/** Display only: a text (a preview of what an install writes) with the home shown as `~` wherever it starts a path. The four replacements, in order: the JSON-escaped
 * home with `\\`, the home with `\`, the home with `/`, and the slash-escaped home (`\/`). The file keeps the real path. */
export function displayText(text: string, home: string): string {
  if (!home) return text;
  const flags = WINDOWS_HOME.test(home) ? "gi" : "g";
  const pattern = (literal: string): RegExp => new RegExp(escapeRegExp(literal), flags);
  const escapedHome = home.replaceAll("\\", "\\\\");
  return text
    .replace(pattern(escapedHome + "\\\\"), "~\\\\")
    .replace(pattern(home + "\\"), "~\\")
    .replace(pattern(home + "/"), "~/")
    .replace(pattern(home.replaceAll("/", "\\/") + "\\/"), "~\\/");
}
