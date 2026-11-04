// Settings → AI and chat → Companion (F3a-tauri, Task 12): the Mac's four cards (SettingsCompanionPage.swift) in its order and words, built from the kit. The page writes only
// companion.humor and companion.seeSessions, each through a spread of the whole block, so the block's other fields stay as the store keeps them. "What the AI saw last" shows
// the lines the last request sent (memory only, in Rust) and is read-only; "Delete all…" asks first, inline, with Cancel. Tests: windows/scripts/settings-tests (pages, drift, map).

import type { CompanionSettings, Humor } from "../companion/core.ts";
import { sentTo } from "../companion/chrome.ts";
import { h } from "../views/dom.ts";
import { button, card, help, notice, row, select, setValue, switchRow, wrapRow } from "./kit.ts";
import { sawText } from "./companionrules.ts";
import type { PageView } from "./ctx.ts";

/** What the Companion tab reads and does, handed in by app.ts: the companion block as it is now, a place to put the whole block back, the saved conversations, and the brain. */
export interface CompanionHost {
  settings(): CompanionSettings;
  put(next: CompanionSettings): void;
  /** The lines the last request sent to the brain (memory only). */
  lastSent(): Promise<string[]>;
  /** How many conversations are saved on this computer. */
  conversations(): Promise<number>;
  /** Deletes every saved conversation; true when the store confirmed it. */
  deleteAll(): Promise<boolean>;
  /** The name the chat's messages go to, for the line under See my sessions. */
  brain(): Promise<string>;
}

const STACK = "display:flex;flex-direction:column;gap:12px";

export function companionTab(o: CompanionHost): PageView {
  // Each write hands the whole block over with one field changed, so the block's other fields are kept as the store has them.
  const write = (patch: Partial<CompanionSettings>): void => o.put({ ...o.settings(), ...patch });

  // Personality: the humor, with the cat's line under it.
  const humor = select([["off", "Off"], ["little", "A little"], ["more", "More"]], o.settings().humor, (v) => write({ humor: v as Humor }));
  const personality = card("Personality", null,
    row("Humor", humor),
    help("The cat's traits come from Cat → Personality. While an agent waits for you, it makes no jokes."),
  );

  // What the chat knows: See my sessions, with the line that says where the messages go (filled once the brain is known).
  const seeSessions = switchRow("See my sessions", { on: o.settings().seeSessions, onChange: (v) => write({ seeSessions: v }) });
  const brainLine = help("");
  const knows = card("What the chat knows", null,
    seeSessions.el,
    brainLine,
    help("Project names and what your Claude Code sessions are doing, never a path or what was written."),
  );

  // Conversations: the count, and Delete all… behind an inline confirm.
  const countRow = row("", wrapRow(button("Delete all…", () => { confirm.hidden = false; })));
  const countLabel = countRow.querySelector<HTMLElement>(".st-labeltext")!;
  // A failed Delete all says so under the count; the next attempt takes the note away.
  const deleteNote = h("div");
  const confirm = h("div", { hidden: true, style: STACK },
    h("div", { class: "st-labeltext", text: "Delete all saved conversations?" }),
    help("Every saved conversation on this computer is deleted. This cannot be undone."),
    wrapRow(
      button("Delete all", () => {
        void o.deleteAll().then((ok) => {
          confirm.hidden = true;
          // Rust emptied what the AI saw last, so the shown box goes with it.
          if (ok) { sawBox.hidden = true; saw.textContent = ""; }
          deleteNote.replaceChildren(...(ok ? [] : [notice("err", "Couldn't delete the conversations.")]));
          loadCount();
        });
      }, "danger"),
      button("Cancel", () => { confirm.hidden = true; }),
    ),
  );
  const loadCount = (): void => {
    void o.conversations().then((n) => { countLabel.textContent = `${n} saved`; });
  };
  const conversations = card("Conversations", null,
    countRow,
    deleteNote,
    confirm,
    help("Kept on this computer, 50 at most; the oldest unpinned goes first."),
  );

  // What the AI saw last: Show reads the lines into a read-only, selectable, scrollable box; Done shuts it.
  const saw = h("pre", { class: "st-saw" });
  const sawBox = h("div", { hidden: true, style: STACK }, saw, wrapRow(button("Done", () => { sawBox.hidden = true; })));
  const sawCard = card("What the AI saw last", null,
    wrapRow(button("Show", () => { void o.lastSent().then((lines) => { saw.textContent = sawText(lines); sawBox.hidden = false; }); })),
    sawBox,
    help("Kept in memory only, gone when NotchMeow quits."),
  );

  const el = h("div", { style: STACK }, personality, knows, conversations, sawCard);
  const sync = (): void => {
    setValue(humor, o.settings().humor);
    seeSessions.set(o.settings().seeSessions);
  };
  sync();
  loadCount();
  void o.brain().then((name) => { brainLine.textContent = sentTo(name); });
  return { el, sync, dispose: () => {} };
}
