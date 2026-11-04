// What a settings save leaves behind (Task 2 of the Settings polish). The window applies a change at once; when the store refuses the latest save, the window goes back to
// the last value the store confirmed and says so where the change was made. Only the latest save's refusal reverts, so an older refusal that a newer save has overtaken
// never undoes what the person chose last. Everything decided here is pure: app.ts only wires `makeSaver` to the DOM. Tests: scripts/settings-tests/save.test.mjs (check:settings).
import type { Settings } from "../core/state.ts";
import { cleanCatBlock } from "../cat/display.ts";
import { cleanSidekickSettings } from "../sidekick/core.ts";

export interface SaveOutcome {
  /** The last value the store confirmed, after this save. */
  stored: Settings;
  /** The window goes back to `stored` and redraws the control that was in use. */
  revert: boolean;
}

/** `seq` is this save's number, `latestSeq` the newest number issued when the answer came. */
export function saveOutcome(stored: Settings, next: Settings, ok: boolean, seq: number, latestSeq: number): SaveOutcome {
  if (ok) return { stored: next, revert: false };
  if (seq !== latestSeq) return { stored, revert: false };
  return { stored, revert: true };
}

/** Where a refused save's note goes: in the card of the control that was in use, or on the page strip when no card holds it (or nothing had focus). */
export type NotePlace = "card" | "strip";
export function notePlacement(card: HTMLElement | null): NotePlace {
  return card ? "card" : "strip";
}

/** The window's stored value after a settings-changed echo. The echo is what Rust holds after its command: `save_settings` is a synchronous command, so its events and answers
 * arrive in the order they were made, and an earlier echo can never arrive after a later one. The echo is merged over the stored value, so a partial echo keeps the rest. */
export function storedAfterEcho(stored: Settings, echo: Partial<Settings>): Settings {
  return { ...stored, ...echo };
}

/** The clean-up boot gives the settings, applied to an echo: the cat block and the sidekick object are cleaned only where the echo carries them, so a partial echo stays partial. */
export function tidyEcho(s: Partial<Settings>): Partial<Settings> {
  return {
    ...s,
    ...(s.cat !== undefined ? { cat: cleanCatBlock(s.cat) } : {}),
    ...(s.sidekick !== undefined ? { sidekick: cleanSidekickSettings(s.sidekick) } : {}),
  };
}

/** What the window does with a save: the DOM is behind these ports, so the same flow runs in a test with a rejecting fake. */
export interface SaverPorts {
  /** The store's answer for the whole settings object: true when it was written. */
  write(next: Settings): Promise<boolean>;
  /** Puts `s` on the window's own copy, the one the page reads. */
  show(s: Settings): void;
  /** The control in use and the card it is in, read now (before any await). Null when nothing has focus. */
  focus(): { el: Element; card: HTMLElement | null } | null;
  /** The page on screen now, compared with the page the save was made on. */
  page(): string;
  /** Redraws the controls after a refusal; `only` is the refused control, written even while it is in use. */
  revert(only: Element | null): void;
  /** Says the refusal where `place` is; `card` is set for "card". */
  note(place: NotePlace, card: HTMLElement | null): void;
  /** Takes the note away (after a confirmed save, before a new note, and on a page change). */
  clear(): void;
}

export interface Saver {
  /** The settings the store last confirmed. */
  stored(): Settings;
  /** A settings-changed echo from Rust. */
  echo(s: Partial<Settings>): void;
  /** Applies `next`, asks the store and resolves true when it was confirmed. */
  save(next: Settings): Promise<boolean>;
}

export function makeSaver(ports: SaverPorts, boot: Settings): Saver {
  let stored = boot;
  let latest = 0;
  return {
    stored: () => stored,
    echo: (s) => { stored = storedAfterEcho(stored, s); },
    async save(next) {
      const seq = ++latest;
      // The focus and the page are read before the first await: the answer may come after the person has moved on.
      const at = ports.focus();
      const page = ports.page();
      ports.show(next);
      // A store that rejects the write has refused it: the same as a refusal, so the window goes back and says so.
      const ok = await ports.write(next).catch(() => false);
      const out = saveOutcome(stored, next, ok, seq, latest);
      stored = out.stored;
      if (ok) ports.clear();
      if (out.revert) {
        ports.show(stored);
        ports.clear();
        ports.revert(at?.el ?? null);
        // A note is for the page the change was made on; a page change has already taken the old controls away.
        if (ports.page() === page) ports.note(notePlacement(at?.card ?? null), at?.card ?? null);
      }
      return ok;
    },
  };
}
