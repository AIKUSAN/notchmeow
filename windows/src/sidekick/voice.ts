// The local voice (sub-project F1, spec "The local voice"): a model that runs on this computer may offer a nicer sentence for a note. The template is always shown first and is always
// right; this only makes the one request and guards the swap. What a model is given is the facts the template was written from, picked field by field from a short list: an agent's name,
// a project's basename, counts, up to three file basenames and the state words. Never a command, a path, a prompt or an assistant message: none of them is in a note's facts to begin with, and
// the list below would drop them if they were. The permission line is never reworded. The request itself goes through Rust (`ai_oneshot`), which asks only a model on this computer. Pure
// apart from that call, which is given. Loaded by the plain-Node checks.

import { acceptNicerLine } from "./core.ts";

/** What a one-shot request is: it takes the system text and the prompt and gives one line, or null (no local model, an error, a timeout). */
export type OneShot = (system: string, prompt: string) => Promise<string | null>;

/** The fields of a note's facts a model may see, and no others. */
export const FACT_KEYS = ["agent", "project", "steps", "stepsAtLeast", "files", "more", "errors", "approvals", "end", "quietMinutes", "kind", "counts"] as const;

const SYSTEM = "You reword one short status note about a coding agent for the person who runs it. Keep every number and every name exactly as given and add none. Answer with one plain sentence: no quotes, no list, no markdown, no path.";

/** At most this many file names, each at most 60 characters (the contract's own limits): a fact that is bigger is cut, never sent whole. */
const MAX_FILES = 3;
const MAX_NAME = 60;

const isObj = (x: unknown): x is Record<string, unknown> => x !== null && typeof x === "object" && !Array.isArray(x);

/** The allowed fields of one fact, with strings and lists kept to the sizes a template has. A fact that is not an object has none. */
export function allowedFacts(fact: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!isObj(fact)) return out;
  for (const k of FACT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(fact, k)) continue;
    const v = fact[k];
    if (typeof v === "string") out[k] = v.slice(0, MAX_NAME);
    else if (typeof v === "number" && Number.isFinite(v)) out[k] = v;
    else if (typeof v === "boolean") out[k] = v;
    else if (Array.isArray(v)) out[k] = v.filter((x) => typeof x === "string" || (typeof x === "number" && Number.isFinite(x))).slice(0, MAX_FILES).map((x) => (typeof x === "string" ? x.slice(0, MAX_NAME) : x));
  }
  return out;
}

/** The request for one line of a note: the template and the facts it was written from. Always well under the 1200 characters Rust allows. */
export function voiceRequest(template: string, fact: unknown): { system: string; prompt: string } {
  return { system: SYSTEM, prompt: `Note: ${template}\nFacts: ${JSON.stringify(allowedFacts(fact))}\nReword the note in one sentence.` };
}

/**
 * A nicer sentence for `template`, or null: no local model, any error, an empty answer, the same sentence, or one that fails the contract's check (`acceptNicerLine`: one line of at most
 * 200 characters, no URL, `/`, `\`, backtick or markdown, only numbers that are in the facts, and the agent's name). Never throws.
 */
export async function nicerLine(oneshot: OneShot, template: string, fact: unknown): Promise<string | null> {
  try {
    const { system, prompt } = voiceRequest(template, fact);
    const reply = await oneshot(system, prompt);
    if (typeof reply !== "string") return null;
    const line = reply.trim();
    return line !== "" && line !== template && acceptNicerLine(line, [fact]) ? line : null;
  } catch {
    return null;
  }
}

/** The lines of a note with a nicer sentence in place of each template that got one (line `i` is worded from fact `i`; a line with no fact, like "+2 more", stays). Null when none changed. */
export async function nicerLines(oneshot: OneShot, lines: readonly string[], facts: readonly unknown[]): Promise<string[] | null> {
  const next = await Promise.all(lines.map(async (line, i) => (i < facts.length ? (await nicerLine(oneshot, line, facts[i])) ?? line : line)));
  return next.some((l, i) => l !== lines[i]) ? next : null;
}
