// Subagent kittens (sub-project B, spec §3): a subagent is a kitten of its parent's cat. Each agent pill keeps a list of kittens, and `kittenStep` is the one reducer
// that changes it; `kittenView` is what to draw at a given time and `kittenSlots` says where each kitten sits beside its parent. A port of "Kittens" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/kitten-cases.json; docs/CAT-CONTRACT.md "Kittens"). Pure: the time is in the event, no clock is
// read, nothing is changed in place, and there is no timer. Imports base.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.
//
// A kitten is {id, type, session, state, born, last, until}: `id` the subagent's agent_id, `type` its agent_type, `session` the session it belongs to (or null),
// `state` working, searching, approval or leaving, `born` and `last` the times of its start and its last event (ms, any one clock), `until` null or, once it is
// leaving, the time it is removed. A leaving kitten is dropped by the next event, and kittenView hides it from `until` on.

import { SLEEP_AFTER_MS, own, toolState } from "./base.ts";
import { displayModeOf } from "./display.ts";

/** At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped. */
export const KITTEN_MAX = 8;
/** A kitten that has stopped plays a happy blink for this long (ms), then goes. */
export const KITTEN_LEAVE_MS = 600;
export const KITTEN_STATES = ["working", "searching", "approval", "leaving"] as const;
export type KittenState = (typeof KITTEN_STATES)[number];

export interface Kitten { id: string; type: string; session: string | null; state: KittenState; born: number; last: number; until: number | null }

/** The events kittenStep takes, each with `t` the time in ms. An event that is anything else changes nothing. */
export type KittenEvent = { t: number } & (
  | { type: "start"; id: string; agentType?: string; session?: string }
  | { type: "tool"; id: string; tool?: string }
  | { type: "permission"; id: string }
  | { type: "resolved"; id: string }
  | { type: "stop"; id: string }
  | { type: "end"; session?: string }
  | { type: "sweep" }
  | { type: "tick" }
);

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const isKittenId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;
const typeOfAgent = (v: unknown): string => (typeof v === "string" ? v.slice(0, 64) : "");
const sessionOf = (v: unknown): string | null => (isKittenId(v) ? v : null);

/** A kitten list as an app may hold it, made safe: entries that are not kittens, or repeat an id, are dropped; every entry is a fresh object. */
export function cleanKittens(list: unknown): Kitten[] {
  const out: Kitten[] = [], seen = new Set<string>();
  for (const k of Array.isArray(list) ? list : []) {
    if (!isPlain(k) || !isKittenId(k.id) || seen.has(k.id) || !(KITTEN_STATES as readonly unknown[]).includes(k.state) || !finite(k.born) || !finite(k.last)) continue;
    seen.add(k.id);
    out.push({ id: k.id, type: typeOfAgent(k.type), session: sessionOf(k.session), state: k.state as KittenState, born: k.born, last: k.last, until: k.state === "leaving" && finite(k.until) ? k.until : null });
  }
  return out;
}

const capKittens = (L: Kitten[]): Kitten[] => {
  while (L.length > KITTEN_MAX) {
    let o = 0;
    for (let i = 1; i < L.length; i++) if (L[i].born < L[o].born) o = i;
    L.splice(o, 1);
  }
  return L;
};

/**
 * The reducer. `list` is one pill's kittens, `ev` an event {type, t, ...} with `t` the time in ms; the result is a new list and nothing is changed.
 *   start       {id, agentType, session}   SubagentStart: a kitten, working. A second start for an id that is there only refreshes it.
 *   tool        {id, tool}                 a Pre/PostToolUse that carries an agent_id: searching when `tool` is a search tool (toolState), else working.
 *   permission  {id}                       a PermissionRequest from the subagent: approval.
 *   resolved    {id}                       that request was answered: back to working.
 *   stop        {id}                       SubagentStop: leaving for KITTEN_LEAVE_MS, then gone.
 *   end         {session}                  the parent stopped or its session ended: with a `session`, only that session's kittens go, and the ones with no session; without one, every kitten goes.
 *   sweep                                  the cat's sleep timer fired: a kitten whose last event is SLEEP_AFTER_MS or more ago is gone (its stop never came).
 *   tick                                   nothing but the time.
 * Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or for a kitten that is already leaving, changes nothing: a late tool
 * event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to show. An event that is not an object, has no finite `t` or has an
 * unknown type returns the list as it is (cleaned). Never throws.
 */
export function kittenStep(list: unknown, ev: unknown): Kitten[] {
  let L = cleanKittens(list);
  if (!isPlain(ev) || !finite(ev.t)) return L;
  const t = ev.t, at = (id: unknown) => L.findIndex((k) => k.id === id && k.state !== "leaving"), set = (i: number, p: Partial<Kitten>) => { L[i] = { ...L[i], ...p }; };
  L = L.filter((k) => k.state !== "leaving" || (k.until ?? 0) > t);
  switch (ev.type) {
    case "start": {
      if (!isKittenId(ev.id)) break;
      const i = L.findIndex((k) => k.id === ev.id);
      if (i >= 0 && L[i].state !== "leaving") { set(i, { last: t, type: typeOfAgent(ev.agentType) || L[i].type, session: sessionOf(ev.session) || L[i].session }); break; }
      if (i >= 0) L.splice(i, 1);
      L.push({ id: ev.id, type: typeOfAgent(ev.agentType), session: sessionOf(ev.session), state: "working", born: t, last: t, until: null });
      capKittens(L);
      break;
    }
    case "tool": { const i = at(ev.id); if (i >= 0) set(i, { state: toolState(ev.tool), last: t }); break; }
    case "permission": { const i = at(ev.id); if (i >= 0) set(i, { state: "approval", last: t }); break; }
    case "resolved": { const i = at(ev.id); if (i >= 0) set(i, { state: L[i].state === "approval" ? "working" : L[i].state, last: t }); break; }
    case "stop": { const i = at(ev.id); if (i >= 0) set(i, { state: "leaving", last: t, until: t + KITTEN_LEAVE_MS }); break; }
    case "end": { const q = sessionOf(ev.session); L = q === null ? [] : L.filter((k) => k.session !== null && k.session !== q); break; }
    case "sweep": L = L.filter((k) => t - k.last < SLEEP_AFTER_MS); break;
  }
  return L;
}

const sortKittens = (clean: Kitten[]): Kitten[] =>
  clean.map((k, i) => ({ k, i })).sort((a, b) => Number(b.k.state === "approval") - Number(a.k.state === "approval") || b.k.born - a.k.born || b.i - a.i).map((x) => x.k);

/** The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`, a later start first when they tie). */
export const kittenOrder = (list: unknown): Kitten[] => sortKittens(cleanKittens(list));

/** What is drawn at `now` (ms): the kittens in kittenOrder, without a leaving kitten whose time is up. A `now` that is not a number hides nothing. */
export const kittenView = (list: unknown, now: unknown): Kitten[] =>
  sortKittens(cleanKittens(list).filter((k) => k.state !== "leaving" || !finite(now) || (k.until ?? 0) > now));

export interface KittenPlace {
  unit: "D" | "H";
  max: number;
  d?: number;
  x0?: number;
  y0?: number;
  step?: number;
  align?: "start" | "center";
  moreAt?: readonly [number, number];
  moreSize?: number;
  label?: { x: number; y: number; size: number };
}

/**
 * Where kittens sit, pinned by kitten-cases.json. Every number is a multiple of a unit: `D`, the parent's head width, with the origin at the parent's head centre (x to
 * the right, y down), or `H`, the pill's height, with the origin at the pill's trailing edge (the kittens' x is negative, inside it) and the middle of its height. `d` is
 * a kitten's head width. `align` 'start': the i-th kitten is at x0 + i * step; 'center': the row is centred on x0. `max` is the most kittens drawn; the rest is "+N", at
 * `moreAt` (default: the next slot after the last one) in text `moreSize` high. `label` is for the pair in the compact notch, which has no room beside it: only a count "×N".
 */
export const KITTEN_PLACES: Readonly<Record<string, KittenPlace>> = {
  bigExpanded: { unit: "D", max: 3, d: 15 / 58, x0: 24 / 58, y0: 34 / 58, step: 18 / 58, align: "start", moreSize: 0.2 },
  bigCompact: { unit: "D", max: 2, d: 12 / 20, x0: 22 / 20, y0: 5 / 20, step: 13 / 20, align: "start", moreAt: [42 / 20, -10 / 20], moreSize: 0.25 },
  pairCompact: { unit: "D", max: 0, label: { x: 1.1, y: 0.3, size: 0.5 } },
  pairExpanded: { unit: "D", max: 3, d: 15 / 58, x0: 0, y0: 34 / 58, step: 18 / 58, align: "center", moreAt: [0, 50 / 58], moreSize: 0.2 },
  pill: { unit: "H", max: 3, d: 15 / 28, x0: -17.5 / 28, y0: 0, step: -16 / 28, align: "start", moreSize: 0.36 },
};

/** The place kittens go for the big cat (and, in Two cats mode, for cat 2): bigExpanded or bigCompact; in Two cats mode pairExpanded or pairCompact. An agent pill uses `pill`. */
export const kittenPlaceOf = (mode: unknown, expanded: unknown): string =>
  displayModeOf(mode) === "two" ? (expanded ? "pairExpanded" : "pairCompact") : expanded ? "bigExpanded" : "bigCompact";

export interface KittenSlot { id: string; state: string; x: number; y: number; d: number }
export interface KittenSlots {
  place: string;
  unit: "D" | "H" | null;
  count: number;
  shown: KittenSlot[];
  more: number;
  moreAt: { x: number; y: number; size: number } | null;
  label: { text: string; x: number; y: number; size: number } | null;
}

/**
 * The slots for one parent's kittens in one place. `kittens` is what kittenView returned (already in order). `shown` is the first `max` kittens as {id, state, x, y, d};
 * `more` how many are left over; `moreAt` {x, y, size} or null when none is left over; `label` null, or for pairCompact {text: "×N", x, y, size} when there is a kitten.
 * An unknown place shows nothing.
 */
export function kittenSlots(place: unknown, kittens: unknown): KittenSlots {
  const P = typeof place === "string" && own(KITTEN_PLACES, place) ? KITTEN_PLACES[place] : null;
  const L = (Array.isArray(kittens) ? kittens : []).filter((k): k is Record<string, unknown> => isPlain(k) && isKittenId(k.id)), count = L.length;
  if (!P) return { place: String(place), unit: null, count, shown: [], more: 0, moreAt: null, label: null };
  const n = Math.min(count, P.max), step = P.step ?? 0, x0 = P.x0 ?? 0, y0 = P.y0 ?? 0, x = (i: number) => (P.align === "center" ? x0 + (i - (n - 1) / 2) * step : x0 + i * step), more = P.label ? 0 : count - n;
  return {
    place: place as string, unit: P.unit, count,
    shown: L.slice(0, n).map((k, i) => ({ id: k.id as string, state: typeof k.state === "string" ? k.state : "working", x: x(i), y: y0, d: P.d ?? 0 })),
    more,
    moreAt: more > 0 ? { x: P.moreAt ? P.moreAt[0] : x0 + P.max * step, y: P.moreAt ? P.moreAt[1] : y0, size: P.moreSize ?? 0 } : null,
    label: P.label && count > 0 ? { text: `×${count}`, x: P.label.x, y: P.label.y, size: P.label.size } : null,
  };
}
