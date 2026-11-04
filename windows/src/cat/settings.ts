// The Cat section's stored settings: what Settings → Cat saves, cleaned. A port of "Stored settings" in design/prototype/cat-core.js (the
// tie-breaker; fixture tests/fixtures/cat/settings-cases.json, docs/CAT-CONTRACT.md "Stored settings"). A settings file can be hand-edited,
// copied from an older build or half written, so everything that reads one passes it through cleanCatSettings first and uses only the result.
// Raw in, clean out, never a throw. The shape is the same raw or clean, and the Rust side (cat_settings.rs) holds the same value:
//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.
// Imports only base.ts, presets.ts and personality.ts, so the plain-Node checks (npm run check:cat) can load it.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { PERSONAS, TRAIT_KEYS, normPers, personaNamed } from "./personality.ts";
import type { Persona, Traits } from "./types.ts";

/** "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style. */
export const FOLLOW = "follow";
export type Follow = typeof FOLLOW;
/** The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful. */
export const MOTION_STYLES = ["playful", "classic"] as const;
export type MotionStyle = (typeof MOTION_STYLES)[number];
/** The collar styles, frozen contract values in this order (A-0b): band and tag, band, neckerchief, and off, the default. */
export const COLLAR_STYLES = ["tag", "band", "kerchief", "off"] as const;
export type CollarStyle = (typeof COLLAR_STYLES)[number];

const isMotion = (v: unknown): v is MotionStyle => (MOTION_STYLES as readonly unknown[]).includes(v);
const isCollar = (v: unknown): v is CollarStyle => (COLLAR_STYLES as readonly unknown[]).includes(v);
const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/** A stored global motion style to a style; anything else (`follow` included) is Playful. */
export const motionStyleOf = (v: unknown): MotionStyle => (isMotion(v) ? v : "playful");
/** A stored global collar style to a style; anything else (`follow` included) is `off`. */
export const collarStyleOf = (v: unknown): CollarStyle => (isCollar(v) ? v : "off");
/** A cat's own motion: `follow` or a style. Anything else is `follow`: no valid override. */
export const motionOverrideOf = (v: unknown): Follow | MotionStyle => (isMotion(v) ? v : FOLLOW);
/** A cat's own collar: `follow` or one of the four styles (`off` is an override like any other). Anything else is `follow`. */
export const collarOverrideOf = (v: unknown): Follow | CollarStyle => (isCollar(v) ? v : FOLLOW);
/** A stored cat ID to a cat ID. An unknown ID, or anything that is not a string, is Shrimpy. */
export const catIdOf = (v: unknown): string => ((CAT_IDS as readonly unknown[]).includes(v) ? (v as string) : "shrimpy");

const sameTraits = (a: Traits, b: Traits) => TRAIT_KEYS.every((k) => Math.abs(a[k] - b[k]) <= 1e-9);

/**
 * A stored personality to a clean one: {preset, energy, curiosity, chatty, affection, sass, mischief}. It may be an object, or the JSON text of
 * one. Text that is not JSON, and JSON that is not an object, give Balanced. The traits go through normPers (held to 0…1, missing or not a
 * number is 0.5). `custom` is how a hand-tuned personality is stored: the preset is kept only when it names one of the six AND the traits are
 * still that preset's (within 1e-9); anything else, a missing or unknown name included, is `custom`.
 */
export function cleanPersonality(raw: unknown): Persona {
  let v = raw;
  if (typeof v === "string") {
    try { v = JSON.parse(v); } catch { return personaNamed("balanced"); }
  }
  if (!isPlain(v)) return personaNamed("balanced");
  const o = v, traits = normPers(o), name = o.preset;
  const named = typeof name === "string" && own(PERSONAS, name) ? name : null;
  return { preset: named && sameTraits(traits, PERSONAS[named]) ? named : "custom", ...traits };
}

export interface CatEntry { motion: Follow | MotionStyle; collar: Follow | CollarStyle; personality: Persona }
export interface CatSettings {
  character: string;
  motionStyle: MotionStyle;
  collar: CollarStyle;
  furLines: boolean;
  cats: Record<string, CatEntry>;
}

/** Everything Settings saves, cleaned. Never throws; unknown keys are dropped; the result always holds all 16 cats, in CAT_IDS order. */
export function cleanCatSettings(raw: unknown): CatSettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  const cats: Record<string, unknown> = isPlain(r.cats) ? r.cats : {};
  const out: CatSettings = { character: catIdOf(r.character), motionStyle: motionStyleOf(r.motionStyle), collar: collarStyleOf(r.collar), furLines: r.furLines === true, cats: {} };
  for (const id of CAT_IDS) {
    const c = own(cats, id) && isPlain(cats[id]) ? cats[id] : {};
    out.cats[id] = { motion: motionOverrideOf(c.motion), collar: collarOverrideOf(c.collar), personality: cleanPersonality(c.personality) };
  }
  return out;
}

/** What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality. */
export const defaultCatSettings = (): CatSettings => cleanCatSettings(null);

/** "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The character and the global settings stay. */
export function applyToAllCats(settings: unknown, id: unknown): CatSettings {
  const s = cleanCatSettings(settings), from = s.cats[catIdOf(id)], out: CatSettings = { ...s, cats: {} };
  for (const c of CAT_IDS) out.cats[c] = { motion: from.motion, collar: from.collar, personality: { ...from.personality } };
  return out;
}

/** The motion style a cat plays: its own override, else the global style. */
export function motionFor(settings: unknown, id: unknown): MotionStyle {
  const s = cleanCatSettings(settings), m = s.cats[catIdOf(id)].motion;
  return m === FOLLOW ? s.motionStyle : m;
}

/** The collar style a cat wears (when it has a colour to wear): its own override, else the global style. */
export function collarFor(settings: unknown, id: unknown): CollarStyle {
  const s = cleanCatSettings(settings), c = s.cats[catIdOf(id)].collar;
  return c === FOLLOW ? s.collar : c;
}

export interface EngineCfg { motion: MotionStyle; override: Record<string, MotionStyle>; pers: Record<string, Persona> }

/** The shared settings an engine reads (the `cfg` of BotEngine, without zoomAfter): the global style, an override for each cat that has one, every cat's personality. */
export function engineCfg(settings: unknown): EngineCfg {
  const s = cleanCatSettings(settings), override: Record<string, MotionStyle> = {}, pers: Record<string, Persona> = {};
  for (const id of CAT_IDS) {
    const c = s.cats[id];
    if (c.motion !== FOLLOW) override[id] = c.motion;
    pers[id] = c.personality;
  }
  return { motion: s.motionStyle, override, pers };
}

/** The part of the engine's shared `catCfg` that Settings fills (engine.ts declares the rest). */
export interface LiveCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  /** The cat the island, the pills, the drop view and the greeting wear: a cat ID. */
  character?: string;
  /** The collar the Main cat wears: its own style, else the global one. */
  collar?: string;
  /** The collar every coat wears: its own style, else the global one (`collarFor` of each of the 16 cats). */
  collars?: Record<string, string>;
  /** Optional fur strands on the big cat. */
  fur?: boolean;
}

/** Puts clean settings into the shared config, in place: engines hold a reference to it. Returns the clean settings. */
export function applyCatSettings(cfg: LiveCfg, settings: unknown): CatSettings {
  const s = cleanCatSettings(settings), e = engineCfg(s);
  cfg.motion = e.motion;
  cfg.override = e.override;
  cfg.pers = e.pers;
  cfg.character = s.character;
  cfg.collar = collarFor(s, s.character);
  cfg.collars = Object.fromEntries(CAT_IDS.map((id) => [id, collarFor(s, id)]));
  cfg.fur = s.furLines;
  return s;
}

// ── Edits: each Settings row changes one thing and gets a whole clean value back ───────────────────────────────────────────────────────────
// They take a clean CatSettings and return a new one, never touching the input; the result goes through cleanCatSettings, so a bad value is the
// neutral one and an unknown cat is Shrimpy.
const edited = (s: CatSettings, patch: Partial<CatSettings>): CatSettings => cleanCatSettings({ ...s, ...patch });
const entryEdited = (s: CatSettings, id: unknown, patch: Partial<CatEntry>): CatSettings => {
  const k = catIdOf(id);
  return edited(s, { cats: { ...s.cats, [k]: { ...s.cats[k], ...patch } } });
};
/** The Character row. */
export const withCharacter = (s: CatSettings, id: unknown): CatSettings => edited(s, { character: catIdOf(id) });
/** The Motion style row. */
export const withMotionStyle = (s: CatSettings, v: unknown): CatSettings => edited(s, { motionStyle: motionStyleOf(v) });
/** The Collar row. */
export const withCollar = (s: CatSettings, v: unknown): CatSettings => edited(s, { collar: collarStyleOf(v) });
/** The Fur lines row. */
export const withFurLines = (s: CatSettings, on: unknown): CatSettings => edited(s, { furLines: on === true });
/** The This cat's motion row: `follow` or a style, for one cat. */
export const withCatMotion = (s: CatSettings, id: unknown, v: unknown): CatSettings => entryEdited(s, id, { motion: motionOverrideOf(v) });
/** The This cat's collar row: `follow` or a style, for one cat. */
export const withCatCollar = (s: CatSettings, id: unknown, v: unknown): CatSettings => entryEdited(s, id, { collar: collarOverrideOf(v) });
/** The Personality row and its sliders: a whole personality (a preset from `personaNamed`, or what `slide` returns) for one cat. */
export const withPersonality = (s: CatSettings, id: unknown, p: unknown): CatSettings => entryEdited(s, id, { personality: cleanPersonality(p) });
