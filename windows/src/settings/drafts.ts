// The typed-but-unsaved text of the Settings fields, and whether each field has a stored value. Pure: no storage, no DOM. The page never holds a stored secret, so "dirty"
// means "something typed" (spaces alone are not a draft), and Remove is the explicit way to clear a stored value. Port of the Mac's SettingsDraftBook.swift, the one
// rule the Settings keys share. Tests: windows/scripts/settings-tests (check:settings).

import type { Presence } from "./status.ts";

/** A card's Save may start a write only when none of its writes is in flight (a second press cannot write newer text while the first is still being written). */
export function canStartWrite(writing: boolean): boolean {
  return !writing;
}

/** Save is off while a write runs, and when nothing writable is typed. */
export function saveDisabled(writing: boolean, dirty: boolean): boolean {
  return writing || !dirty;
}

export class DraftBook {
  #present: Map<string, Presence>;
  #keys: ReadonlySet<string>;
  #typed = new Map<string, string>();

  /** `present` holds what the window read; `keyIds` are the keys it reads at boot. A key in `keyIds` that has no reading is never writable. */
  constructor(present: Record<string, Presence>, keyIds: readonly string[] = []) {
    this.#present = new Map(Object.entries(present));
    this.#keys = new Set(keyIds);
  }

  /** What is typed in a field (empty when nothing is). */
  text(id: string): string {
    return this.#typed.get(id) ?? "";
  }

  edit(id: string, text: string): void {
    this.#typed.set(id, text);
  }

  /** A draft is text with something other than spaces in it. */
  isDirty(id: string): boolean {
    return this.text(id).trim() !== "";
  }

  anyDirty(ids: readonly string[]): boolean {
    return ids.some((id) => this.isDirty(id));
  }

  /** The field has a stored value. */
  isSaved(id: string): boolean {
    return this.#present.get(id) === "present";
  }

  /** The store could not be read for this field: it is neither saved nor absent, and nothing is written to it. */
  isUnreadable(id: string): boolean {
    return this.#present.get(id) === "unreadable";
  }

  /** The presence as read, or undefined when the window never read this key. Undefined is not "absent": a caller decides what an unread key shows. */
  presenceOf(id: string): Presence | undefined {
    return this.#present.get(id);
  }

  /** Whether a write or a removal may go to this key: never while the store cannot be read, and never for a key the window should have read and did not. A key outside the key list (the added server's) is writable. */
  canWrite(id: string): boolean {
    const p = this.#present.get(id);
    if (p === undefined) return !this.#keys.has(id);
    return p !== "unreadable";
  }

  /** The fields of `ids` with a draft that may be written: what a card's Save writes. */
  writableDirty(ids: readonly string[]): string[] {
    return ids.filter((id) => this.canWrite(id) && this.isDirty(id));
  }

  /** After a write or a removal that succeeded: the presence is set, and the typed text is cleared when it is still the text that was sent (`sent`). Text typed while the
   * write ran is kept and the field stays a draft. A removal sends nothing, so its typed text is cleared. */
  markSaved(id: string, present: boolean, sent?: string): void {
    if (sent === undefined || this.text(id) === sent) this.#typed.delete(id);
    this.#present.set(id, present ? "present" : "absent");
  }

  /** A fresh look at the store (on boot, or Check again): the presence is set, and the typed text is kept. */
  setPresence(id: string, presence: Presence): void {
    this.#present.set(id, presence);
  }

  /** The window was hidden: nothing typed is kept. */
  clearTyped(): void {
    this.#typed.clear();
  }
}
