// Focus awareness on Windows and Linux (the spec docs/superpowers/specs/2026-10-17-focus-awareness-design.md): when a permission request or a question comes from a
// session whose app is the frontmost app, NotchMeow answers "ask" at once and stays silent. The Mac's twin is NotchBuddy/Sources/App/FocusAware.swift; the shared
// rules are pinned to it by scripts/cat-tests/focusaware.test.mjs. Pure: every time, read and timer is a parameter; the imports are projects/core.ts (the wait label)
// and steps.ts (the step's verb).

import { waitLabel } from "../projects/core.ts";
import { stepVerb } from "./steps.ts";

export const MARK_LIFETIME_MS = 600_000;
export const MARKS_MAX = 64;
/** How long the frontmost app may take to read before the mark is made without it (the read is a user-visible wait, so it stays short). */
export const FOREGROUND_WAIT_MS = 300;
/** The session's own events that end its mark (the Mac's eight, in its order). */
export const ENDING_EVENTS: readonly string[] = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "UserPromptSubmit", "Stop", "StopFailure", "Interrupt", "SessionEnd"];

export type ForegroundKind = "windows" | "x11" | "none";
export type FocusKind = "permission" | "question";
export interface FocusApp { name: string; words: string }
export interface FocusHost { apps: readonly FocusApp[] }
export interface FocusMark { sessionId: string; pillId: string; host: string; kind: FocusKind; words: string | null; at: number }

const CLAUDE_TAG = "claude-desktop";
const SESSION_KEY_MAX = 128;

const WIN_CLAUDE: readonly FocusApp[] = [{ name: "Claude.exe", words: "Claude App" }];
const WIN_VSCODE: readonly FocusApp[] = [
  { name: "Code.exe", words: "VS Code" }, { name: "Code - Insiders.exe", words: "VS Code" }, { name: "VSCodium.exe", words: "VS Code" }, { name: "Cursor.exe", words: "Cursor" },
];
const WIN_TERMINAL: readonly FocusApp[] = [{ name: "WindowsTerminal.exe", words: "Windows Terminal" }];
const X11_VSCODE: readonly FocusApp[] = [
  { name: "Code", words: "VS Code" }, { name: "Code - Insiders", words: "VS Code" }, { name: "VSCodium", words: "VS Code" }, { name: "Cursor", words: "Cursor" },
];
// Names are the documented defaults, not verified here (spec call 5): a wrong one only means today's card.
const X11_TERMINALS = new Map<string, readonly FocusApp[]>([
  ["kitty", [{ name: "kitty", words: "kitty" }]],
  ["wezterm", [{ name: "org.wezfurlong.wezterm", words: "WezTerm" }]],
  ["alacritty", [{ name: "Alacritty", words: "Alacritty" }]],
  ["ghostty", [{ name: "com.mitchellh.ghostty", words: "Ghostty" }]],
]);

/** The setting reads on unless it is stored as false (absent or not a Boolean is on). */
export function focusEnabled(stored: unknown): boolean {
  return stored !== false;
}

/** The session key the Sidekick ledger uses (sidekick-core.js eventFrom): the first non-empty of session_id and conversation_id, cut to 128 code points, else "unknown". */
export function focusSessionKey(p: { session_id?: unknown; conversation_id?: unknown }): string {
  const id = [p.session_id, p.conversation_id].find((x): x is string => typeof x === "string" && x !== "");
  if (id === undefined) return "unknown";
  const cps = Array.from(id);
  return cps.length > SESSION_KEY_MAX ? cps.slice(0, SESSION_KEY_MAX).join("") : id;
}

/**
 * The session's host on this OS, or null when no app can be named. The Claude app tag comes first, then VS Code (its own terminal can inherit WT_SESSION), then the
 * terminal. On X11 the Claude app has no window to name.
 */
export function focusHost(p: { nm_agent?: unknown; term_program?: unknown; wt_session?: unknown }, kind: ForegroundKind): FocusHost | null {
  if (kind === "none") return null;
  const claude = p.nm_agent === CLAUDE_TAG;
  const term = typeof p.term_program === "string" ? p.term_program.toLowerCase() : "";
  if (kind === "windows") {
    if (claude) return { apps: WIN_CLAUDE };
    if (term === "vscode") return { apps: WIN_VSCODE };
    if (typeof p.wt_session === "string" && p.wt_session !== "") return { apps: WIN_TERMINAL };
    return null;
  }
  if (claude) return null;
  if (term === "vscode") return { apps: X11_VSCODE };
  const row = X11_TERMINALS.get(term);
  return row ? { apps: row } : null;
}

/** The matched app's words, or null: a null or empty foreground never matches, and the name is compared ignoring case. */
export function matchForeground(host: FocusHost, foreground: string | null | undefined): string | null {
  if (!foreground) return null;
  const f = foreground.toLowerCase();
  const app = host.apps.find((a) => a.name.toLowerCase() === f);
  return app ? app.words : null;
}

/**
 * The frontmost app's name, or null when the read rejects or `waitMs` passes first. The timer is cleared when the read wins. Every time and timer is a parameter.
 */
export function raceForeground(
  read: () => Promise<string | null>,
  waitMs: number,
  setTimer: (fn: () => void, ms: number) => unknown,
  clearTimer: (t: unknown) => void,
): Promise<string | null> {
  return new Promise((resolve) => {
    const timer = setTimer(() => resolve(null), waitMs);
    const done = (value: string | null) => {
      clearTimer(timer);
      resolve(value);
    };
    Promise.resolve().then(read).then(done, () => done(null));
  });
}

/** What stepBackFor takes: the gates' inputs, the frontmost app's read with its timer, the clock's now, and the pill of a request's agent tag (hooks.ts's rule). */
export interface StepBackInput {
  kind: ForegroundKind;
  enabled: boolean;
  paused: boolean;
  route: string;
  payload: { hook_event_name?: unknown; tool_name?: unknown; nm_agent?: unknown; term_program?: unknown; wt_session?: unknown; session_id?: unknown; conversation_id?: unknown };
  read: () => Promise<string | null>;
  waitMs: number;
  setTimer: (fn: () => void, ms: number) => unknown;
  clearTimer: (t: unknown) => void;
  now: number;
  pillIdOf: (agent: unknown) => string;
}

/**
 * A permission request's mark, or null: the gates first (no read is asked for when one fails), then the frontmost app's name within the wait, then the match. A question
 * (AskUserQuestion) is a question with no words. The read is the caller's, so the page's own foreground read is never named here.
 */
export function stepBackFor(i: StepBackInput): Promise<FocusMark | null> {
  const p = i.payload;
  if (i.kind === "none" || !i.enabled || i.paused || p.hook_event_name !== "PermissionRequest" || i.route === "chat") return Promise.resolve(null);
  const host = focusHost(p, i.kind);
  if (host === null) return Promise.resolve(null);
  return raceForeground(i.read, i.waitMs, i.setTimer, i.clearTimer).then((fg): FocusMark | null => {
    const words = matchForeground(host, fg);
    if (words === null) return null;
    const tool = typeof p.tool_name === "string" ? p.tool_name : "";
    const question = tool === "AskUserQuestion";
    return {
      sessionId: focusSessionKey(p),
      pillId: i.pillIdOf(p.nm_agent),
      host: words,
      kind: question ? "question" : "permission",
      words: question ? null : stepVerb(tool),
      at: i.now,
    };
  });
}

/**
 * stepBackFor for the page: a decision that throws, or whose read or timer rejects, is no mark, so the event still reaches handleHook (with none). Never rejects.
 */
export function stepBackOrNone(i: StepBackInput): Promise<FocusMark | null> {
  try {
    return stepBackFor(i).then((m) => m, () => null);
  } catch {
    return Promise.resolve(null);
  }
}

/** The note on the pill's card: "Waiting in <host>", then ": <step words>" when there are words (the Mac's noteText). */
export function noteText(host: string, words: string | null): string {
  const label = waitLabel(host);
  return typeof words === "string" && words !== "" ? `${label}: ${words}` : label;
}

/** The amber dot on the pill: while a mark lives, in the badge place, and never with a badge or a waiting card. */
export function showsDot(markLive: boolean, badgeShown: boolean, cardWaiting: boolean): boolean {
  return markLive && !badgeShown && !cardWaiting;
}

/** Whether the overview's note takes cat 2's second line while a mark lives (unless that line is itself a waiting alert). */
export function showsNoteOverSecondLine(markLive: boolean, secondWaiting: boolean): boolean {
  return markLive && !secondWaiting;
}

/**
 * Whether cat 2's second line says it waits, by its own state: approval ("waiting for you") and question ("has a question"). The line stays when it is itself a
 * waiting card, as on the Mac; on Windows the line's own state is the truth, so the note never hides a line that does not wait.
 */
export function lineWaits(state: string | undefined | null): boolean {
  return state === "approval" || state === "question";
}

function isLive(m: FocusMark, now: number): boolean {
  const age = now - m.at;
  return age < MARK_LIFETIME_MS && age > -MARK_LIFETIME_MS;
}

function newest(list: readonly FocusMark[]): FocusMark | null {
  return list.reduce<FocusMark | null>((best, m) => (best === null || m.at > best.at ? m : best), null);
}

/** The marks after a new one: the same session's mark on the same pill is replaced, the dead are dropped, the newest MARKS_MAX are kept. The input is never changed. */
export function recordMark(marks: readonly FocusMark[], mark: FocusMark): FocusMark[] {
  const kept = marks.filter((m) => !(m.pillId === mark.pillId && m.sessionId === mark.sessionId) && isLive(m, mark.at));
  kept.push({ ...mark });
  if (kept.length <= MARKS_MAX) return kept;
  return kept.sort((a, b) => a.at - b.at).slice(kept.length - MARKS_MAX);
}

/** The marks after a session's event: every mark of the session ends on an ending event, except the --ask twin of a question. The input is never changed. */
export function endMarks(marks: readonly FocusMark[], sessionId: string, event: string, tool: string): FocusMark[] {
  const ends = ENDING_EVENTS.includes(event) && !(event === "PreToolUse" && tool === "AskUserQuestion");
  return marks.filter((m) => !(ends && m.sessionId === sessionId));
}

export function liveMarks(marks: readonly FocusMark[], now: number): FocusMark[] {
  return marks.filter((m) => isLive(m, now));
}

export function markForPill(marks: readonly FocusMark[], pillId: string, now: number): FocusMark | null {
  return newest(liveMarks(marks, now).filter((m) => m.pillId === pillId));
}

export function markForSession(marks: readonly FocusMark[], sessionId: string, now: number): FocusMark | null {
  return newest(liveMarks(marks, now).filter((m) => m.sessionId === sessionId));
}

/** The Sidekick-clock time (ms) at which a mark made at `markAt` ends: the rest of its lifetime from `now`, added to `nowMs` (the Sidekick's clock may be skewed). */
export function lapseMs(markAt: number, now: number, nowMs: number): number {
  return nowMs + (markAt + MARK_LIFETIME_MS - now);
}
