// Personality: six traits, 0 to 1, that bend the behaviour a cat already has. 0.5 is neutral, so the
// Balanced preset is exactly the approved motion. Any coat can wear any personality.
// A port of the personality section of design/prototype/cat-core.js, the tie-breaker.
// Imports only base.ts, so the plain-Node checks (npm run check:cat) can load it.

import { clamp, own, tm } from "./base.ts";
import type { Persona, Traits } from "./types.ts";

export type TraitKey = keyof Traits;

/** key, label, low end, high end: what Settings shows for each slider. */
export const TRAITS: readonly (readonly [TraitKey, string, string, string])[] = [
  ["energy", "Energy", "sleepy", "bouncy"],
  ["curiosity", "Curiosity", "aloof", "nosy"],
  ["chatty", "Chattiness", "quiet", "talkative"],
  ["affection", "Affection", "independent", "cuddly"],
  ["sass", "Sass", "easy-going", "grumpy"],
  ["mischief", "Mischief", "well-behaved", "troublemaker"],
];

export const PERSONAS: Record<string, Traits & { label: string }> = {
  balanced: { label: "Balanced", energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 },
  chill: { label: "Chill", energy: 0.12, curiosity: 0.35, chatty: 0.3, affection: 0.65, sass: 0.3, mischief: 0.2 },
  grumpy: { label: "Grumpy", energy: 0.4, curiosity: 0.3, chatty: 0.45, affection: 0.15, sass: 0.95, mischief: 0.3 },
  sweet: { label: "Sweet", energy: 0.5, curiosity: 0.55, chatty: 0.55, affection: 1, sass: 0.1, mischief: 0.3 },
  hyper: { label: "Hyper", energy: 1, curiosity: 0.9, chatty: 0.75, affection: 0.5, sass: 0.3, mischief: 1 },
  chatty: { label: "Chatty", energy: 0.6, curiosity: 0.7, chatty: 1, affection: 0.6, sass: 0.35, mischief: 0.5 },
};
export const TRAIT_KEYS: readonly TraitKey[] = TRAITS.map((t) => t[0]);

/** Traits as stored: a missing, non-numeric or NaN trait becomes 0.5, anything else is held to 0…1 (a settings file can be hand-edited). */
export function normPers(P: Partial<Record<TraitKey, unknown>> | null | undefined): Traits {
  const o = {} as Traits;
  for (const k of TRAIT_KEYS) {
    const raw = P ? P[k] : undefined;
    const v = typeof raw === "number" && Number.isFinite(raw) ? raw : 0.5;
    o[k] = clamp(v, 0, 1);
  }
  return o;
}

/**
 * What a personality changes, as numbers. The engine reads only these.
 *   speed, hop, blinkEvery, gaze, earFlickEvery, chatter, slowBlinkEvery are multipliers (1 at neutral);
 *   pupil, smile, skew, blush, lid and earBack are added to the resting pose (0 at neutral);
 *   idle says which idle habits are on; poke is the reaction to a poke; pokeHiss adds a hiss to it.
 */
export function persMultipliers(P0: Partial<Record<TraitKey, unknown>> | null | undefined) {
  const P = normPers(P0), energy = P.energy, sass = P.sass, aff = P.affection;
  return {
    speed: tm(energy, 0.55, 1.5), hop: tm(energy, 0.45, 1.4), blinkEvery: tm(energy, 1.4, 0.75), pupil: (energy - 0.5) * 0.3,
    lid: Math.max(Math.max(0, 0.5 - energy), Math.max(0, sass - 0.55) * 0.55),
    gaze: tm(P.curiosity, 0.35, 1.2), earFlickEvery: tm(P.curiosity, 1.6, 0.6), chatter: tm(P.chatty, 0.3, 1.4),
    smile: (aff - 0.5) * 0.5 - Math.max(0, sass - 0.5) * 1.1, blush: Math.max(0, aff - 0.6) * 0.9, slowBlinkEvery: tm(aff, 1.6, 0.5),
    skew: Math.max(0, sass - 0.5) * 0.9, earBack: Math.max(0, sass - 0.55) * 0.45,
    idle: { yawn: energy < 0.3, zoomies: P.mischief > 0.75 && energy > 0.7, mew: P.chatty > 0.7, purr: aff > 0.75, hmph: sass > 0.75, wink: P.mischief > 0.65 },
    poke: aff > 0.75 && sass < 0.4 ? ("love" as const) : ("annoyed" as const), pokeHiss: sass > 0.7,
  };
}
export type Multipliers = ReturnType<typeof persMultipliers>;

/** A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced. */
export function personaNamed(name: string): Persona {
  const k = own(PERSONAS, name) ? name : "balanced";
  const { label: _label, ...traits } = PERSONAS[k];
  return { preset: k, ...traits };
}

/** Moving a slider: the new value (held to 0…1) and the preset becomes 'custom'. An unknown trait or a bad value changes nothing. */
export function slide(pers: Persona, trait: string, value: number): Persona {
  return (TRAIT_KEYS as readonly string[]).includes(trait) && typeof value === "number" && Number.isFinite(value)
    ? { ...pers, [trait]: clamp(value, 0, 1), preset: "custom" }
    : { ...pers };
}
