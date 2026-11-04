// Settings → Sidekick (sub-project F1, spec "Settings"; Settings restyle, Task 10): the Sidekick tab's five cards, built from the kit. Notes: the master switch, the recaps and
// the stuck nudges (each with a made-up example), the four stuck kinds under Choose which, and the permission line, locked on with no stored key. Quiet times and Today so far
// are F3a, shown disabled. Where its words come from: plain rules or a model on this computer. Muted notes: Unmute for each muted kind. Every change hands the whole object to
// the window through the clean-up of src/sidekick/settings.ts; the section keeps no state of its own. No timer: the switches are built once and set in place, and an example
// box is shown only when its button is pressed. Tests: windows/scripts/sidekick-tests/settings.test.mjs and windows/scripts/settings-tests/pages.test.mjs.

import { KIND_LABELS, mutedKinds, withLocal, withMuted, withSidekickOn, withUnmuted } from "../sidekick/settings.ts";
import type { NoteKind, SidekickSettings } from "../sidekick/core.ts";
import { h } from "../views/dom";
import { button, card, chip, details, help, row, switchRow, wrapRow } from "./kit.ts";
import { COMES_WITH_F3A, NOTHING_LEAVES, PERMISSION_LINE, STUCK_KINDS, STUCK_NAMES, example, stuckSwitch } from "./sidekicktab.ts";

/** What the section needs from the window: the `sidekick` object as it is now, a place to put the new one, and (optionally) a look for a local model. */
export interface SidekickHost {
  sidekick(): SidekickSettings;
  put(next: SidekickSettings): void;
  /** The name of the local model the wording would come from, or null when there is none. Missing: the "Found" line is not shown. */
  found?(): Promise<string | null>;
}

const STACK = "display:flex;flex-direction:column;gap:12px";

/** A made-up example of one kind: a button that shows (or hides) its line inside the card. The box is sized to its text. */
function exampleControl(kind: NoteKind, head: string): HTMLElement[] {
  const box = h("div", { class: "st-example", hidden: true },
    h("div", { class: "st-example-head", text: head }),
    h("div", { class: "st-example-line", text: example(kind) ?? "" }),
  );
  const toggle = button("Show me an example", () => {
    box.hidden = !box.hidden;
    toggle.setAttribute("aria-expanded", String(!box.hidden));
  });
  toggle.setAttribute("aria-expanded", "false");
  return [wrapRow(toggle), box];
}

/** A radio's checked state, written only when the person is not on it (the kit's setValue is for values). */
function setChecked(el: HTMLInputElement, on: boolean): void {
  if (el !== document.activeElement && el.checked !== on) el.checked = on;
}

export function sidekickSection(host: SidekickHost): { el: HTMLElement; sync(): void; dispose(): void } {
  let foundText: string | null = null;
  const write = (next: SidekickSettings): void => {
    host.put(next);
    paint();
  };
  const setKind = (kind: NoteKind, on: boolean): void => write(on ? withUnmuted(host.sidekick(), kind) : withMuted(host.sidekick(), kind));
  const setStuck = (on: boolean): void => {
    let next = host.sidekick();
    for (const kind of STUCK_KINDS) next = on ? withUnmuted(next, kind) : withMuted(next, kind);
    write(next);
  };

  // Notes.
  const s0 = host.sidekick();
  const masterSwitch = switchRow("Show notes from the sidekick", { on: s0.on, onChange: (v) => write(withSidekickOn(host.sidekick(), v)) });
  const recap = switchRow("Away recaps", {
    on: !mutedKinds(s0).includes("recap"),
    help: "A short recap when you come back and an agent did something.",
    onChange: (v) => setKind("recap", v),
  });
  const stuck = switchRow("Stuck nudges", { on: true, help: "A nudge when an agent looks stuck.", onChange: setStuck });
  const kindRows = STUCK_NAMES.map(({ kind, label }) => ({
    kind,
    sw: switchRow(label, { on: !mutedKinds(s0).includes(kind), onChange: (v) => setKind(kind, v) }),
  }));
  const notes = card("Notes", null,
    masterSwitch.el,
    recap.el,
    ...exampleControl("recap", "Claude Code · Welcome back"),
    stuck.el,
    ...exampleControl("stuck.loop", "Claude Code · needs a look"),
    details("Choose which", ...kindRows.map((k) => k.sw.el)),
    switchRow("Permission line", { on: true, disabled: true, help: PERMISSION_LINE, onChange: () => {} }).el,
    switchRow("Jokes and moods", { on: false, chip: COMES_WITH_F3A, disabled: true, onChange: () => {} }).el,
  );

  // Quiet times: F3a, all off and disabled.
  const quiet = card("Quiet times", { summary: COMES_WITH_F3A },
    help("Coming soon: hold notes while an app is full screen, during calls and screen sharing, and at hours you choose. Until then notes never show over your work or while you type."),
    ...["Full-screen apps", "Calls and screen sharing", "Chosen hours"].map((label) =>
      switchRow(label, { on: false, chip: COMES_WITH_F3A, disabled: true, onChange: () => {} }).el),
  );

  // Where its words come from: plain rules, or a model on this computer (the Found line under it), and My main AI, which comes later.
  const plain = h("input", { type: "radio", name: "sidekick-words", value: "plain" }) as HTMLInputElement;
  const local = h("input", { type: "radio", name: "sidekick-words", value: "local" }) as HTMLInputElement;
  const main = h("input", { type: "radio", name: "sidekick-words", value: "main" }) as HTMLInputElement;
  main.disabled = true;
  plain.addEventListener("change", () => { if (plain.checked) write(withLocal(host.sidekick(), false)); });
  local.addEventListener("change", () => { if (local.checked) write(withLocal(host.sidekick(), true)); });
  const found = h("div", { class: "hint" });
  const words = card("Where its words come from", null,
    h("label", { class: "st-radio" }, plain, h("span", { text: "Plain rules" })),
    h("label", { class: "st-radio" }, local, h("span", { text: "A model on this computer" })),
    ...(host.found ? [found] : []),
    h("label", { class: "st-radio" }, main, h("span", { text: "My main AI" }), chip(COMES_WITH_F3A)),
    help(NOTHING_LEAVES),
    help("Only a model on this computer is ever asked, and only with the words of the note."),
  );

  // Today so far: F3a, one button that is not yet ready.
  const today = button("Show today's notes", () => {});
  today.disabled = true;
  const todayCard = card("Today so far", { summary: COMES_WITH_F3A }, wrapRow(today));

  // Muted notes: each muted kind with its Unmute, or the line that nothing is muted.
  const mutedBox = h("div", { style: STACK });
  const muted = card("Muted notes", null,
    mutedBox,
    help("A note you dismiss twice is muted until you unmute it here."),
  );

  function paint(): void {
    const s = host.sidekick();
    const off = (kind: NoteKind): boolean => mutedKinds(s).includes(kind);
    masterSwitch.set(s.on);
    recap.set(!off("recap"), { disabled: !s.on });
    const st = stuckSwitch((kind) => off(kind as NoteKind));
    stuck.set(st.on, { chip: st.detail, disabled: !s.on });
    for (const k of kindRows) k.sw.set(!off(k.kind), { disabled: !s.on });
    setChecked(plain, !s.local);
    setChecked(local, s.local);
    found.textContent = foundText === null ? "No local model found" : `Found: ${foundText}`;
    const list = mutedKinds(s);
    mutedBox.replaceChildren(...(list.length
      ? list.map((kind) => {
        const unmute = button("Unmute", () => setKind(kind, true));
        unmute.setAttribute("aria-label", `Unmute ${KIND_LABELS[kind]}`);
        return row(KIND_LABELS[kind], wrapRow(unmute));
      })
      : [help("Nothing is muted")]));
  }

  const el = h("div", { style: STACK }, notes, quiet, words, todayCard, muted);
  paint();
  if (host.found) void host.found().then((name) => { foundText = name; paint(); });
  // Nothing to stop: the section has no timer and no observer.
  return { el, sync: paint, dispose: () => {} };
}
