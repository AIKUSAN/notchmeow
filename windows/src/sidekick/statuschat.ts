// "What's Claude doing?" in the chat (sub-project F1, spec "What's Claude doing?"): a short message that is exactly that question is answered here, on this computer, from the ledger. The
// answer is a card of NotchMeow's own. It is never added to the conversation: it is not in `State.chatHistory`, it is not in what any model is sent, and the question never reaches a model, a
// cloud one least of all. This module imports nothing that talks to a model. Pure; loaded by the plain-Node checks.

import type { Recap, StatusQuestion } from "./core.ts";

/** The words of the chip in the chat's empty conversation, and the question it asks. */
export const STATUS_CHIP_TEXT = "What's Claude doing?";

/** The line under the answer: where it came from. */
export const STATUS_CAPTION = "From NotchMeow, on this computer";

/** One answer from NotchMeow itself, shown in the chat after `afterCount` of the conversation's messages. It is the app's, not the conversation's. */
export interface LocalAnswer {
  id: number;
  /** How many messages of the conversation came before it, so the card stands where it was asked. */
  afterCount: number;
  /** What the user asked, as they typed it. */
  question: string;
  /** The lines of the answer: the ledger's templates, an agent's name, counts and basenames. */
  lines: string[];
  /** The facts the lines were written from (the only thing the local voice may be given). */
  facts: unknown[];
}

/** What the answer needs of the Sidekick. */
export interface StatusSource {
  matchStatus(text: string): StatusQuestion;
  status(agentId: string | null): Recap;
}

/** The answer to `text`, or null when it is a normal chat message (anything longer, or different: a real question that merely contains the words goes to the model as usual). */
export function answerStatus(text: string, source: StatusSource, afterCount: number, id: number): LocalAnswer | null {
  const m = source.matchStatus(text);
  if (!m.matched) return null;
  const status = source.status(m.agentId);
  return { id, afterCount, question: text.trim(), lines: [...status.lines], facts: [...status.facts] };
}

/**
 * The chat's rows in the order they are shown: the conversation's messages, with each local answer after the message it followed (a question and its card), and the answers asked
 * after the last message at the end. Returns what to draw, not elements: the view builds them.
 */
export function interleave<T>(messages: readonly T[], answers: readonly LocalAnswer[]): Array<{ message: T } | { answer: LocalAnswer }> {
  const rows: Array<{ message: T } | { answer: LocalAnswer }> = [];
  const placed = new Set<number>();
  messages.forEach((message, i) => {
    for (const a of answers) if (a.afterCount === i && !placed.has(a.id)) { rows.push({ answer: a }); placed.add(a.id); }
    rows.push({ message });
  });
  for (const a of answers) if (!placed.has(a.id)) rows.push({ answer: a });
  return rows;
}
