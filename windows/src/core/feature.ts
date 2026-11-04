// Which model setting answers a message. No imports besides a type, so the plain-Node
// check in scripts/check-ai-ui.mjs can load this file as it is.

import type { Feature } from "./bridge";

/** What the rule needs from a message of the conversation; `ChatMessage` has it. */
export interface MaybeWithFiles {
  readonly attachments?: readonly string[];
}

/**
 * File questions when the message being sent carries a file or any earlier message of the
 * conversation did; Chat otherwise. A file's text stays in the history, so every follow-up must use
 * the setting the user picked for files: on the Chat route it would reach whichever model Chat uses,
 * a cloud one included.
 *
 * The conversation's own messages decide, never `State.droppedFile`: it is never cleared, so it
 * could not tell a conversation that holds a file from one that doesn't. A drop or a new chat
 * empties `State.chatHistory`, and the rule starts over with it.
 */
export function featureFor(current: readonly string[], history: readonly MaybeWithFiles[]): Feature {
  const carriesFile = (attachments: readonly string[] | undefined) => (attachments?.length ?? 0) > 0;
  return carriesFile(current) || history.some((m) => carriesFile(m.attachments)) ? "files" : "chat";
}

/** The drop-related fields of `State`. */
export interface DropState {
  droppedFile: unknown;
  promptContext: unknown;
  pendingAttachment: string | null;
  dropReader: string | null;
}

/** A drop the file layer rejected: the chat row draws its chip from `droppedFile`, so forget it all. */
export function forgetDrop(s: DropState): void {
  s.droppedFile = null;
  s.promptContext = null;
  s.pendingAttachment = null;
  s.dropReader = null;
}

/**
 * The note that replaces a busy countdown once the automatic retries have run out. It keeps the
 * provider name from Rust's "Claude is busy. Trying again in 20 s." (`errors.rs`) and drops the
 * countdown; the Mac says the same in `AIMessages.error`.
 */
export function stillBusy(countdownNote: string): string {
  return countdownNote.replace(/ is busy\. Trying again in \d+ s\./, " is still busy. Try again in a moment.");
}

/**
 * What Settings shows after a failed key check (Rust's words from `ai_list_models`). Only a refused or missing
 * key is "rejected" and gets the red mark; offline, unreachable and the rest ("Couldn't reach OpenAI. Check
 * your connection.") are shown plain, so being offline never reads as a bad key.
 */
export function keyCheckFailure(err: string): { text: string; rejected: boolean } {
  const text = err.replace(/^Error:\s*/, "");
  return { text, rejected: /key (was rejected|is missing)\.$/.test(text) };
}
