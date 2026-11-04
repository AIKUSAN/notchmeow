// Which cat appears where (sub-project B, spec §2). A cat stands for an agent's pill, and the big cat shows the focused pill. For the chosen display mode,
// `castOf` says which coat each place wears: the big cat, a second cat (Two cats), the pills and the 2×2 grid, the drop view and the launch greeting. A port of
// "Display modes: which cat appears where (the cast)" in design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/cast-cases.json;
// docs/CAT-CONTRACT.md "The cast"). Pure: no clock, no random numbers. Imports base.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.
//
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.

import { BUSY, STATES, own } from "./base.ts";
import type { StateName } from "./base.ts";
import { catIdOf } from "./settings.ts";
import { cleanAgentCats, cleanPair, defaultAgentCat, displayModeOf, isAgentPill, isPillId } from "./display.ts";
import type { DisplayMode } from "./display.ts";

/** The most pills the row and the 2×2 grid hold (the island shows `otherTasks.slice(0, 4)`). */
export const PILL_ROW = 4;

/** How busy an agent is, for the busiest-other rule: 0 waits for you (approval or question), 1 error, 2 working, thinking or searching, 3 anything else. */
export const busyRank = (st: unknown): 0 | 1 | 2 | 3 => (st === "approval" || st === "question" ? 0 : st === "error" ? 1 : BUSY.has(st as StateName) ? 2 : 3);
const rankKey = (a: readonly number[], b: readonly number[]): number => {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
};

/** One pill of the island, in the app's order: the pill ID, its state (anything that is not one of STATES is idle) and the time of its last event in ms (any one clock). */
export interface CastTask { id: string; state: string; last: number }
export interface CastPill { pill: string; cat: string }
export interface Cast {
  mode: DisplayMode;
  /** The big cat: the focused pill (null when there is none) and its coat. */
  big: { pill: string | null; cat: string };
  /** Two cats mode: the busiest other agent (`pill` is null when no other agent exists: cat 2 idles, no badge) and pair cat 2. Null in the other modes. */
  second: { pill: string | null; cat: string } | null;
  /** The row and the grid: the tasks other than the focus (and other than `second.pill`), the first PILL_ROW of them, in the app's order. */
  pills: CastPill[];
  /** The cat of the drop view and the drag ghost: the big cat's. */
  drop: string;
  /** The launch greeting: the cat that falls in (the Main cat), the pair that arrives together (Two cats mode) or null, and the four session cats in the grid's cell order. */
  greeting: { cat: string; pair: [string, string] | null; sessions: string[] };
}

/**
 * The cast of one mode. `input` is {tasks, focusId, mainCat, pair, agentCats}: `tasks` the island's pills (a pill listed twice counts once, an ID that is not a pill ID
 * is skipped, a `last` that is not a finite number is 0), `focusId` the focused pill or null, and the three settings as stored (they are cleaned here, so a raw value
 * is fine). An agent that has no stored coat and no default wears the Main cat here: agentCatFor gives it one when it is first seen, before it is drawn. Never throws.
 */
export function castOf(mode: unknown, input: unknown): Cast {
  const m = displayModeOf(mode), inp: Record<string, unknown> = input !== null && typeof input === "object" && !Array.isArray(input) ? (input as Record<string, unknown>) : {};
  const main = catIdOf(inp.mainCat), pr = cleanPair(inp.pair), map = cleanAgentCats(inp.agentCats), seen = new Set<string>(), list: CastTask[] = [];
  for (const t of Array.isArray(inp.tasks) ? inp.tasks : []) {
    if (t === null || typeof t !== "object" || Array.isArray(t) || !isPillId(t.id) || seen.has(t.id)) continue;
    seen.add(t.id);
    list.push({ id: t.id, state: (STATES as readonly unknown[]).includes(t.state) ? (t.state as string) : "idle", last: typeof t.last === "number" && Number.isFinite(t.last) ? t.last : 0 });
  }
  const focus = isPillId(inp.focusId) ? inp.focusId : null;
  const agentCat = (id: string): string => (own(map, id) ? map[id] : defaultAgentCat(id) || main);
  const catOf = (id: string | null): string => (m === "perAgent" && id !== null && isAgentPill(id) ? agentCat(id) : main);
  const big = { pill: focus, cat: m === "two" ? pr[0] : catOf(focus) };
  let second: Cast["second"] = null;
  if (m === "two") {
    let bestId: string | null = null, bestKey: number[] = [];
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.id === focus || !isAgentPill(t.id)) continue;
      const key = [busyRank(t.state), -t.last, i];
      if (bestId === null || rankKey(key, bestKey) < 0) { bestId = t.id; bestKey = key; }
    }
    second = { pill: bestId, cat: pr[1] };
  }
  const pills = list.filter((t) => t.id !== focus && !(second && t.id === second.pill)).slice(0, PILL_ROW).map((t) => ({ pill: t.id, cat: catOf(t.id) }));
  return { mode: m, big, second, pills, drop: big.cat, greeting: { cat: main, pair: m === "two" ? pr : null, sessions: [0, 1, 2, 3].map((i) => (pills[i] ? pills[i].cat : main)) } };
}
