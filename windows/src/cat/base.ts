// The cat's small shared pieces: helpers, the state tables and the mouth table.
// A port of the first sections of design/prototype/cat-core.js, which is the tie-breaker:
// if this file and the fixtures in tests/fixtures/cat/ disagree, cat-core.js is right.
//
// Imports only the generated theme (plain data), so the plain-Node checks (npm run check:cat) can load it as it is.

import { THEME } from "../theme.generated.ts";

export const TAU = Math.PI * 2;

export type EaseName = "out" | "inOut" | "back" | "lin" | "in";

/** The easings, by the names the fixtures and the tweens use. */
export const EZ: Record<EaseName, (t: number) => number> = {
  out: (t) => 1 - Math.pow(1 - t, 3),
  inOut: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  back: (t) => 1 + 2.7 * Math.pow(t - 1, 3) + 1.7 * Math.pow(t - 1, 2),
  lin: (t) => t,
  in: (t) => t * t * t,
};

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
/** 0 up to 1 as t runs from a to b. */
export const seg = (t: number, a: number, b: number) => clamp((t - a) / (b - a), 0, 1);
export const wrapA = (a: number) => ((((a + Math.PI) % TAU) + TAU) % TAU) - Math.PI;

/** "#RRGGBB" to [r, g, b], each 0 to 255. */
export const hex = (h: string): [number, number, number] => [
  parseInt(h.slice(1, 3), 16),
  parseInt(h.slice(3, 5), 16),
  parseInt(h.slice(5, 7), 16),
];

/** The seeded PRNG: a 32-bit LCG. The same seed gives the same sequence on every platform. */
export function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => (s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296;
}

/** Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1. */
export const tm = (v: number, lo: number, hi: number) =>
  v < 0.5 ? lerp(lo, 1, v / 0.5) : lerp(1, hi, (v - 0.5) / 0.5);

export const own = (o: object, k: string) => Object.prototype.hasOwnProperty.call(o, k);

// ── State tables (colours and tints are upstream's) ───────────────────────────

export const STATES = [
  "idle", "working", "thinking", "searching", "approval", "question",
  "error", "finished", "ratelimit", "sleeping", "dizzy",
] as const;
export type StateName = (typeof STATES)[number];

/** The colour of each state. The cat core pins them (tests/fixtures/cat/), and shared/theme.json's generator reads them from it into the theme file. */
export const COL: Record<StateName, string> = THEME.state.color;
export const TINT: Record<StateName, number> = {
  idle: 0, working: 0.72, thinking: 0.72, searching: 0.72, approval: 0.78, question: 0.75,
  error: 0.78, finished: 0.35, ratelimit: 0.72, sleeping: 0.32, dizzy: 0.7,
};
/** The glow behind a working cat, for the states that have one (the cat core pins it, as it pins COL). */
export const GLOW: Partial<Record<StateName, string>> = THEME.state.glow;
export type BadgeKind = "dots" | "bang" | "question" | "dot";
export const BADGE: Partial<Record<StateName, BadgeKind>> = {
  working: "dots", thinking: "dots", searching: "dots", approval: "bang",
  question: "question", error: "dot", finished: "dot", ratelimit: "dot",
};

// ── Mouth ─────────────────────────────────────────────────────────────────────

export type MouthKey = "mouth" | "smile" | "tongue" | "mround" | "mskew" | "wavy";
/** open, smile (-1 frown … 1 smile), tongue, round (wide D … 'o'), skew, wavy: the six animatable values. */
export const MKEYS: readonly MouthKey[] = ["mouth", "smile", "tongue", "mround", "mskew", "wavy"];

/** The rest mouth of each state, in MKEYS order. */
export const MOUTH: Record<StateName, readonly number[]> = {
  idle: [0, 0, 0, 0, 0, 0], working: [0, 0.05, 0.35, 0, 0, 0], thinking: [0, -0.15, 0, 0, 0.7, 0],
  searching: [0, 0, 0, 0, 0, 0], approval: [0, 0.1, 0, 0.35, 0, 0], question: [0.13, 0, 0, 1, 0, 0],
  error: [0, -0.8, 0, 0, 0, 0], finished: [0, 1, 0, 0, 0, 0], ratelimit: [0.3, 0, 0.85, 0.2, 0, 0],
  sleeping: [0, 0.1, 0, 1, 0, 0], dizzy: [0, 0, 0.45, 0, 0, 1],
};

/** The mouth pose of each emote, shared by both motion styles: [pose, duration in ms]. */
export const EMOUTH: Record<string, readonly [Partial<Record<MouthKey, number>>, number]> = {
  love: [{ smile: 0.8 }, 1800],
  surprised: [{ mouth: 0.6, mround: 1 }, 1000],
  proud: [{ smile: 0.75, mskew: 0.45 }, 1800],
  wink: [{ tongue: 0.8, smile: 0.4, mskew: 0.3 }, 1100],
  yawn: [{ tongue: 0.35, mround: 0.15 }, 1100],
  happy: [{ mouth: 0.5, smile: 1 }, 1300],
  annoyed: [{ smile: -0.7, mskew: -0.6 }, 850],
};

/** Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring. */
export function mouthFx(st: StateName, T: number): number {
  switch (st) {
    case "searching": {
      const ph = T % 2.6;
      return ph < 1.1 ? Math.sin((Math.PI * ph) / 1.1) * (0.24 + 0.07 * Math.sin(T * TAU * 9)) : 0;
    }
    case "approval": {
      const ph = (T % 1.4) / 1.4;
      return ph < 0.28 ? 0.5 * Math.sin((Math.PI * ph) / 0.28) : 0;
    }
    case "ratelimit":
      return 0.07 * Math.sin(T * TAU * 2.8);
    case "sleeping":
      return 0.07 * Math.max(0, Math.sin(T * 1.5));
    default:
      return 0;
  }
}

/** The states in which an agent is working: they keep the work clock running. */
export const BUSY: ReadonlySet<StateName> = new Set<StateName>(["working", "thinking", "searching"]);

// ── The work clock ────────────────────────────────────────────────────────────

/** An agent that finishes after this much working, thinking or searching earns zoomies (ms). */
export const ZOOM_AFTER_MS = 5 * 60 * 1000;

export interface WorkClock { busySince: number | null; workedFor: number }

/**
 * The work clock. Working, thinking and searching keep it running; approval and question pauses neither stop
 * nor reset it; every other state ends the run and stores how long it lasted in `workedFor` (never negative,
 * even if the clock steps back). Pure: pass the clock in, get the next one back. `busySince` is null while no run is open.
 */
export function workClockStep(clock: WorkClock, state: StateName, nowMs: number): WorkClock {
  const c = { busySince: clock.busySince, workedFor: clock.workedFor };
  if (BUSY.has(state)) {
    if (c.busySince === null) c.busySince = nowMs;
  } else if (state !== "approval" && state !== "question") {
    c.workedFor = c.busySince === null ? 0 : Math.max(0, nowMs - c.busySince);
    c.busySince = null;
  }
  return c;
}
export const zoomiesOnFinish = (workedForMs: number, thresholdMs = ZOOM_AFTER_MS) => workedForMs >= thresholdMs;

// ── Searching ─────────────────────────────────────────────────────────────────

/**
 * The tool names that mean "searching" (tests/fixtures/cat/search-tools.json): web search, web fetch, grep and glob. Claude Code's come from the repo's
 * hook mapping, Gemini CLI's from the installed CLI, Codex's are unverified. Exact and case-sensitive on the `tool_name` the hook relay delivers:
 * no prefix or MCP matching. A name that is missing only means the cat stays in "working" for that tool.
 */
export const SEARCH_TOOLS = {
  claude: ["WebSearch", "WebFetch", "Grep", "Glob"],
  gemini: ["google_web_search", "web_fetch", "grep_search", "search_file_content", "glob"],
  codex: ["web_search", "grep_files"],
} as const;
const SEARCH_SET: ReadonlySet<string> = new Set<string>(Object.values(SEARCH_TOOLS).flat());
/** True for a tool name that means searching. Anything that is not a string is not a search. */
export const isSearchTool = (name: unknown): boolean => typeof name === "string" && SEARCH_SET.has(name);
/** The state of an agent that is running this tool: `searching` for a search tool, `working` for any other. */
export const toolState = (name: unknown): "searching" | "working" => (isSearchTool(name) ? "searching" : "working");

// ── Sleeping ──────────────────────────────────────────────────────────────────

/** An idle cat falls asleep after this long with no agent event (ms). */
export const SLEEP_AFTER_MS = 10 * 60 * 1000;
/**
 * How long until a cat in `state` falls asleep, `quietMs` after the last agent event: 0 once it is due. Only an idle cat sleeps; every other state,
 * an approval and a question included, is null. A quiet time that is negative or not a number counts as 0 (a clock that stepped back).
 */
export const sleepDelay = (state: string, quietMs: number): number | null =>
  state === "idle" ? Math.max(0, SLEEP_AFTER_MS - Math.max(0, Number.isFinite(quietMs) ? quietMs : 0)) : null;
/** What wakes a sleeping cat: an agent event (`hook`), a hover or a click. A key, a scroll or a drag does not. In Playful it wakes with zoomies. */
export const WAKE_EVENTS: readonly string[] = ["hook", "hover", "click"];
export const wakes = (kind: unknown): boolean => typeof kind === "string" && WAKE_EVENTS.includes(kind);
