// Giving each agent its cat (sub-project B, spec §1): Claude Code is Shrimpy and Codex is Momo; any other agent, the first time it is seen, gets a random coat that
// no other agent and not the Main cat uses, and keeps it. A port of "Display modes: giving agents their cats" in design/prototype/cat-core.js (the tie-breaker;
// fixture tests/fixtures/cat/agent-cat-cases.json). Pure: the random source is injected (`rand()`, 0 up to, not including, 1), so a test repeats.
// Imports base.ts, presets.ts, settings.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { catIdOf } from "./settings.ts";
import { DEFAULT_AGENT_CATS, cleanAgentCats, defaultAgentCat, isAgentPill } from "./display.ts";

export type Rand = () => number;

/**
 * One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1, and `avoid` is a
 * coat that is never chosen. A coat nobody uses is chosen at random (rand() is called once, and only then); when every coat is in use, the least-used one is chosen,
 * ties broken in CAT_IDS order (rand() is not called). A `rand` that is not a function, or a number that is not finite, is 0, and 1 or more is the last free coat.
 */
export function pickCat(taken: readonly string[], rand?: unknown, avoid?: string | null): string {
  const use = new Map<string, number>();
  for (const c of taken) use.set(c, (use.get(c) ?? 0) + 1);
  const pool = CAT_IDS.filter((c) => c !== avoid), free = pool.filter((c) => !use.has(c));
  if (free.length) {
    const r = typeof rand === "function" ? (rand as Rand)() : 0;
    return free[Math.min(free.length - 1, Math.max(0, Math.floor(typeof r === "number" && Number.isFinite(r) ? r * free.length : 0)))];
  }
  let best = pool[0];
  for (const c of pool) if ((use.get(c) ?? 0) < (use.get(best) ?? 0)) best = c;
  return best;
}

export interface AgentCatResult { cat: string; agentCats: Record<string, string>; assigned: boolean }

/**
 * The cat of an agent pill: its stored coat, else its default (Claude Code Shrimpy, Codex Momo), else a coat chosen now: random, from those used neither by another
 * agent (a stored one, or a default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see pickCat). `agentCats` in the
 * result is the cleaned map, with the new pill added when `assigned` is true, which is the app's cue to store it, and never to change it by itself afterwards.
 * A pill that is not an agent pill (an integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
 */
export function agentCatFor(pillId: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): AgentCatResult {
  const map = cleanAgentCats(agentCats), main = catIdOf(mainCat);
  if (!isAgentPill(pillId)) return { cat: main, agentCats: map, assigned: false };
  if (own(map, pillId)) return { cat: map[pillId], agentCats: map, assigned: false };
  const d = defaultAgentCat(pillId);
  if (d) return { cat: d, agentCats: map, assigned: false };
  const cat = pickCat([...Object.values({ ...DEFAULT_AGENT_CATS, ...map }), main], rand, null), next = cleanAgentCats({ ...map, [pillId]: cat });
  return { cat, agentCats: next, assigned: own(next, pillId) };
}

/**
 * The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is agentCatFor's rule, with this agent's
 * own coat set aside. Always stored, a default agent included. Returns {cat, agentCats}.
 */
export function rerollAgentCat(pillId: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): { cat: string; agentCats: Record<string, string> } {
  const map = cleanAgentCats(agentCats), main = catIdOf(mainCat);
  if (!isAgentPill(pillId)) return { cat: main, agentCats: map };
  const eff: Record<string, string> = { ...DEFAULT_AGENT_CATS, ...map }, cur = eff[pillId] ?? null;
  delete eff[pillId];
  const cat = pickCat([...Object.values(eff), main], rand, cur);
  return { cat, agentCats: cleanAgentCats({ ...map, [pillId]: cat }) };
}

/** agentCatFor for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map. */
export function assignAgentCats(pillIds: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): Record<string, string> {
  let map = cleanAgentCats(agentCats);
  for (const id of Array.isArray(pillIds) ? pillIds : []) map = agentCatFor(id, map, mainCat, rand).agentCats;
  return map;
}
