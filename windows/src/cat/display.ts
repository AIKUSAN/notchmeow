// The Display settings (sub-project B, spec §1): how the cats are shown. Settings → Cat → Display picks One cat (the Main cat everywhere, the default), A cat for
// each agent, or Two cats (a pair, side by side), and saves a mode, the pair and each agent's coat. A port of "Display modes: the stored settings" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/display-cases.json; docs/CAT-CONTRACT.md "Display settings"). A settings file can be
// hand-edited or half written, so everything that reads one passes it through cleanDisplaySettings first. Raw in, clean out, never a throw. The Rust side
// (src-tauri/src/cat_settings.rs) holds the same block and cleans it the same way.
//
//   { displayMode, pair: [catId, catId], agentCats: { <pillId>: <catId> } }       in the `cat` block of settings.json, beside the Cat settings
//
// cleanCatSettings (settings.ts) still returns only the five Cat settings and drops these keys, so the block is cleaned with both: `cleanCatBlock`.
// Imports base.ts, presets.ts, settings.ts and projects/core.ts, so the plain-Node checks (npm run check:cat, npm run check:projects) can load it.
//
// Sub-project P (projects): the `cat` block also holds `projectCats`, { <folder name>: <catId> } at most 256 deep. It is cleaned by cleanProjectCats (projects/core.ts,
// the typed copy of shared/projects-core.js), kept by every clean-up of the block, and edited by withProjectCat and withoutProjectCat below. Rust: clean_project_cats.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { cleanDesktopSettings, cleanDesktopSpots, desktopSizeOf } from "./desktop.ts";
import type { DesktopSettings } from "./desktop.ts";
import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";
import { cleanWardrobeSettings, outfitIdOf } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";
import { cleanProjectCats } from "../projects/core.ts";

/** The display modes, in the order Settings lists them. Frozen contract values, like the cat IDs: an unknown stored mode is `one`. */
export const DISPLAY_MODES = ["one", "perAgent", "two"] as const;
export type DisplayMode = (typeof DISPLAY_MODES)[number];
export const displayModeOf = (v: unknown): DisplayMode => ((DISPLAY_MODES as readonly unknown[]).includes(v) ? (v as DisplayMode) : "one");

/** Two cats mode's pair before the user picks: Shrimpy and Momo. */
export const DEFAULT_PAIR: readonly [string, string] = ["shrimpy", "momo"];
/** What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen (agentcat.ts). */
export const DEFAULT_AGENT_CATS: Readonly<Record<string, string>> = { integration_claude: "shrimpy", agent_codex: "momo" };
/** A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end. */
export const MAX_AGENT_CATS = 256;
/** A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, the whole string. Names that are prototype members are refused. */
export const PILL_ID = /^[a-z][a-z0-9_-]{1,63}$/;
export const isPillId = (v: unknown): v is string => typeof v === "string" && PILL_ID.test(v) && v !== "constructor" && v !== "prototype";
/** Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill. Every other pill is an integration or an AI provider. */
export const isAgentPill = (v: unknown): v is string => isPillId(v) && (v === "integration_claude" || (v.startsWith("agent_") && v.length > 6));
/** The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or null for a pill that has none. */
export const defaultAgentCat = (id: unknown): string | null => (isPillId(id) && own(DEFAULT_AGENT_CATS, id) ? DEFAULT_AGENT_CATS[id] : null);

const isCatId = (v: unknown): v is string => typeof v === "string" && (CAT_IDS as readonly string[]).includes(v);
const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/**
 * A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole, is Shrimpy and
 * Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
 */
export function cleanPair(raw: unknown): [string, string] {
  let v = raw;
  if (typeof v === "string") {
    try { v = JSON.parse(v); } catch { return [...DEFAULT_PAIR]; }
  }
  if (!Array.isArray(v) || v.length !== 2 || !v.every(isCatId)) return [...DEFAULT_PAIR];
  return v[0] === v[1] ? [v[0], CAT_IDS[(CAT_IDS.indexOf(v[1]) + 1) % CAT_IDS.length]] : [v[0], v[1]];
}

/**
 * A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown
 * pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (agentCatFor gives that agent a
 * coat again). The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
 */
export function cleanAgentCats(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!isPlain(raw)) return out;
  let n = 0;
  for (const id of Object.keys(raw).filter(isPillId).sort()) {
    if (n >= MAX_AGENT_CATS) break;
    const c = raw[id], d = defaultAgentCat(id);
    if (isCatId(c)) { out[id] = c; n++; } else if (d) { out[id] = d; n++; }
  }
  return out;
}

export interface DisplaySettings { displayMode: DisplayMode; pair: [string, string]; agentCats: Record<string, string> }

/** Everything Display saves, cleaned: {displayMode, pair, agentCats}. Never throws. */
export function cleanDisplaySettings(raw: unknown): DisplaySettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  return { displayMode: displayModeOf(r.displayMode), pair: cleanPair(r.pair), agentCats: cleanAgentCats(r.agentCats) };
}

/** What a fresh install holds: One cat, Shrimpy and Momo, no stored agent coats. */
export const defaultDisplaySettings = (): DisplaySettings => cleanDisplaySettings(null);

// ── The whole `cat` block: the Cat settings, the Display settings, the desktop cat's, the wardrobe's and the project cats' (sub-project P) ─────────────────

/** The `cat` block of settings.json, clean: the Cat settings (settings.ts), the Display settings, the desktop cat's (`desktop`, desktop.ts: sub-project H), the wardrobe's (`outfit`, wardrobe.ts: sub-project I) and the project cats (`projectCats`: a folder name to its cat, sub-project P). */
export type CatBlock = CatSettings & DisplaySettings & { desktop: DesktopSettings; outfit: OutfitId; projectCats: Record<string, string> };

/** Cleans the block with all five clean-ups: a clean-up that used cleanCatSettings alone would drop the display keys, `desktop`, `outfit` and `projectCats` at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({
  ...cleanCatSettings(raw), ...cleanDisplaySettings(raw), desktop: cleanDesktopSettings(isPlain(raw) ? raw.desktop : undefined), ...cleanWardrobeSettings(raw),
  projectCats: cleanProjectCats(isPlain(raw) ? raw.projectCats : undefined),
});

/** What a fresh install holds. */
export const defaultCatBlock = (): CatBlock => cleanCatBlock(null);

// ── Edits: each Display row changes one thing and gets a whole clean block back (they never touch their input) ───────────────────────────────

const blockEdited = (b: CatBlock, patch: Partial<DisplaySettings>): CatBlock => cleanCatBlock({ ...b, ...patch });
/** A Cat settings row edit (or a whole new block) put into the block: the display keys the block has are kept, because an edit of the Cat settings does not carry them. */
export const withCatSettings = (b: CatBlock, next: CatSettings | CatBlock): CatBlock => cleanCatBlock({ ...b, ...next });
/** The Display row. */
export const withDisplayMode = (b: CatBlock, v: unknown): CatBlock => blockEdited(b, { displayMode: displayModeOf(v) });
/** One of the pair's pickers: cat 1 (`index` 0) or cat 2 (1). The same coat twice makes cat 2 the next coat (cleanPair). */
export const withPair = (b: CatBlock, index: 0 | 1, id: unknown): CatBlock => {
  const pair: [string, string] = [b.pair[0], b.pair[1]];
  pair[index] = catIdOf(id);
  return blockEdited(b, { pair });
};
/** An agent's cat picker: its coat is stored, and cleanAgentCats keeps the rest. */
export const withAgentCat = (b: CatBlock, pillId: unknown, catId: unknown): CatBlock => blockEdited(b, { agentCats: cleanAgentCats({ ...b.agentCats, [String(pillId)]: catId }) });
/** The desktop cat's settings, changed in part: whether it is out, its size, its spots. Each is cleaned with the rest of the block. */
export const withDesktop = (b: CatBlock, patch: Partial<DesktopSettings>): CatBlock => cleanCatBlock({ ...b, desktop: { ...b.desktop, ...patch } });
export const withDesktopOn = (b: CatBlock, on: boolean): CatBlock => withDesktop(b, { on });
export const withDesktopSize = (b: CatBlock, size: unknown): CatBlock => withDesktop(b, { size: desktopSizeOf(size) });
export const withDesktopSpots = (b: CatBlock, spots: unknown): CatBlock => withDesktop(b, { spots: cleanDesktopSpots(spots) });
/** The Wardrobe section and the two cats' menus: one of the 18 selection IDs (anything else is `auto`). */
export const withOutfit = (b: CatBlock, v: unknown): CatBlock => cleanCatBlock({ ...b, outfit: outfitIdOf(v) });
/** The dice and "Reset to defaults" give back a whole map (rerollAgentCat's and assignAgentCats'). */
export const withAgentCats = (b: CatBlock, agentCats: unknown): CatBlock => blockEdited(b, { agentCats: cleanAgentCats(agentCats) });
/**
 * A project's cat picked: `catKey` is a folder name, `catId` a cat ID. Refused (the block comes back as it was, `b` itself) when the key or the cat is not kept, or
 * when the clean-up at the cap of PROJECT_CATS_MAX would drop a project's cat that `b` already stores (the Mac's updateProjectCats guard: a new project never evicts one).
 */
export const withProjectCat = (b: CatBlock, catKey: unknown, catId: unknown): CatBlock => {
  const key = String(catKey);
  const next = cleanProjectCats({ ...b.projectCats, [key]: catId });
  if (!own(next, key) || Object.keys(b.projectCats).some((k) => !own(next, k))) return b;
  return cleanCatBlock({ ...b, projectCats: next });
};
/** A project's stored cat dropped: the project shows the cat it gets from its name again. */
export const withoutProjectCat = (b: CatBlock, catKey: unknown): CatBlock => {
  const rest: Record<string, string> = { ...b.projectCats };
  delete rest[String(catKey)];
  return cleanCatBlock({ ...b, projectCats: rest });
};
