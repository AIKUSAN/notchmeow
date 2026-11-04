// What the site's cats decide, as plain data in and out (no DOM), so the plain-Node checks (npm run check:cat) can run it.

import { CAT_IDS, PRESETS } from "../cat/presets.ts";
import { OUTFIT_DRAWN, OUTFIT_NAMES } from "../cat/wardrobe.ts";
import type { StateName } from "../cat/base.ts";

/** What the page knows about whether its cats can be seen and how much motion the visitor wants. */
export interface PageState { hidden: boolean; inView: boolean; reduced: boolean }

/** Frames are drawn only while the tab is shown, the cats are on screen and the visitor has not asked for less motion: only `true` counts. */
export const animates = (p: PageState): boolean => p.hidden === false && p.inView === true && p.reduced === false;

/** The two cats of the hero: the coat each wears and which of them the coat row dresses. */
export interface Hero { coats: [string, string]; picked: 0 | 1 }
export const START: Hero = { coats: ["shrimpy", "momo"], picked: 0 };

/** Picks the cat the coat row dresses. Anything but 0 or 1 changes nothing. */
export const pickCat = (h: Hero, i: unknown): Hero => (i === 0 || i === 1 ? { ...h, picked: i } : h);

/** Dresses the picked cat in a coat. A coat that is not one of the sixteen (or not text at all) changes nothing. */
export function pickCoat(h: Hero, id: unknown): Hero {
  if (typeof id !== "string" || !CAT_IDS.includes(id)) return h;
  const coats: [string, string] = [h.coats[0], h.coats[1]];
  coats[h.picked] = id;
  return { ...h, coats };
}

/** The line under the cats: who the coat row dresses. */
export const dressing = (h: Hero): string => `Pick a coat for ${PRESETS[h.coats[h.picked]].label}, the ${h.picked === 0 ? "left" : "right"} cat.`;

/** One button of "How the cats react": the engine state it sets, the words on the button, and the sentence that says what the state means in the notch. */
export interface Reaction { state: StateName; label: string; line: string }
export const REACTIONS: readonly Reaction[] = [
  { state: "working", label: "Working", line: "Claude Code is busy with your task: the cat shows dots while it edits and runs commands." },
  { state: "thinking", label: "Thinking", line: "Claude Code is working out its next step: the cat shows dots, and nothing needs you yet." },
  { state: "approval", label: "Needs your OK", line: "Claude Code wants to run something: the cat shows an amber mark and waits for your click." },
  { state: "question", label: "Has a question", line: "Claude Code is asking you something: the cat shows a question mark and waits for your answer." },
  { state: "finished", label: "Done", line: "The task is done: the cat is marked with a dot in the notch." },
  { state: "error", label: "Something failed", line: "A step failed: the cat is marked with a dot in the notch." },
  { state: "ratelimit", label: "Hit a limit", line: "Claude's usage limit is reached: the cat is marked with a dot until it resets." },
  { state: "sleeping", label: "Asleep", line: "Nothing has happened for a while: the cat dozes until an agent needs it." },
];

/** The outfits "Try an outfit" steps through: the sixteen drawn ones in the wardrobe's order, then bare (null: the engine's word for none). */
export const TRY_OUTFITS: readonly (string | null)[] = [...OUTFIT_DRAWN, null];
/** The next step after step `i`, wrapping round to the first. */
export const nextOutfit = (i: number): number => (i + 1) % TRY_OUTFITS.length;
/** The outfit note under the buttons. */
export const outfitWords = (id: string | null): string => (id === null ? "Nothing on." : `Wearing ${(OUTFIT_NAMES as Record<string, string>)[id]}.`);
