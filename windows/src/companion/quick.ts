// Quick actions and the pasted screenshot (sub-project F3a-tauri, Task 10): the quick card's state, the picture test and the words a failed quick action
// shows, and the one rule that keeps a waiting file across a new chat. Pure apart from the type it takes, so the plain-Node checks can load it. The requests
// are built by quickRequest (core.ts) and the replies cleaned by quickResultClean; the card shows the reply as plain text.

import type { DropState } from "../core/feature.ts";
import { QUICK_NO_VISION } from "./core.ts";

/** The quick card: the last Fix or Rewrite. `text` is plain text; `note` is a line under it (a refusal, a failed copy). */
export interface QuickResult { kind: "fix" | "rewrite"; text: string; running: boolean; cut: boolean; note: string | null }

const PICTURE = /\.(png|jpe?g|gif|webp)$/i;

/** True for a picture's name or path (any case of the picture extensions): a waiting file of this kind gets the screenshot chip. */
export function isImageName(name: string): boolean {
  return PICTURE.test(name);
}

/** The line a failed quick action shows: the vision words for a model that can't see the picture, the event's own words otherwise. */
export function quickNote(e: { type: string; kind?: string; message?: string }): string {
  if (e.type === "problem" && e.kind === "cant_see") return QUICK_NO_VISION;
  return e.message ?? "";
}

/**
 * A new chat forgets the waiting file (`forgetDrop`). The screenshot and Explain flows keep it: this takes it now and returns the function that puts it back
 * after the new chat has started.
 */
export function keepWaiting(s: DropState): () => void {
  const kept = { droppedFile: s.droppedFile, promptContext: s.promptContext, pendingAttachment: s.pendingAttachment, dropReader: s.dropReader };
  return () => Object.assign(s, kept);
}
