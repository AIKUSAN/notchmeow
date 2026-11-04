// The Settings window's layout kit (Settings restyle, "The layout kit"): the card, the row, the switch, the key field, the chips and the buttons every page is built from, so the
// page rules hold by construction. Plain DOM through h(); every function takes plain values and closures. No storage, no timers, no observers: the shell and the app own those.

import { h, clear, dot } from "../views/dom";
import { tone, type Presence } from "./status.ts";
import type { DraftBook } from "./drafts.ts";
import type { SettingsCtx } from "./ctx.ts";
import { tabTitle, type Tab } from "./route.ts";

/** A card: a title, an optional status chip on the right of it, the children, then an optional help line. Every card is the column's width. */
export function card(title: string, opts: { summary?: string | null; footer?: string; dot?: string } | null, ...children: Node[]): HTMLElement {
  const head = h("div", { class: "st-cardhead" },
    opts?.dot ? dot(opts.dot) : null,
    h("h2", { class: "st-cardtitle", text: title }),
    opts?.summary ? chip(opts.summary) : null,
  );
  return h("section", { class: "st-card" }, head, ...children, opts?.footer ? help(opts.footer) : null);
}

let seq = 0;
/** A fresh id, for a label that names a control and for a region a toggle shows. */
const nextId = (): string => `st-lbl-${++seq}`;

/** The controls that are one short thing: a switch, a chip, a button, a range, a number field or a unit's word. A row of only these keeps its label beside them (see rowOf). A field or a
 * pop-up menu is not one: its row keeps the room it grows into and stacks under the label when they do not fit. */
const SHORT = ".switch, .st-chip, button, input[type='range'], input[type='number'], input[type='checkbox'], .hint";
const isShort = (c: Node): boolean => c instanceof HTMLElement && (c.matches(SHORT) || (c.matches(".st-wrap") && c.children.length > 0 && Array.from(c.children).every(isShort)));
/** A row whose controls are all short: its label keeps the line beside them (settings.css, .st-row.st-short). */
const shortRow = (controls: readonly Node[]): boolean => controls.length > 0 && controls.every(isShort);

/** A label on the left and its control on the right. A row of short controls keeps the label and the control on one line whenever the label's text fits beside them: the label keeps a floor
 * of 9em beside a wide control, wraps between words, and breaks a word only when the word is wider than its column (settings.css). Any other row stacks the control under the label when they do not fit,
 * and its help line comes after the control. */
export function row(label: string, control: Node | Node[], note?: string): HTMLElement {
  const controls = Array.isArray(control) ? control : [control];
  const text = h("span", { class: "st-labeltext", text: label });
  if (shortRow(controls)) {
    return rowOf(text, h("div", { class: "st-label" }, text), controls, note ? h("div", { class: "st-under" }, help(note)) : null);
  }
  // The help is a line of its own after the control, so the label's width is its text only (the label is not as wide as the note) and the row reads label, control, help: the
  // Mac's order. The control names it with aria-describedby.
  const line = note ? help(note) : null;
  if (line) {
    line.id = nextId();
    for (const c of controls) if (c instanceof HTMLElement && c.matches("input, select, textarea, button")) c.setAttribute("aria-describedby", line.id);
  }
  return rowOf(text, h("div", { class: "st-label" }, text), controls, line ? h("div", { class: "st-under" }, line) : null);
}

/** The label's text names each form control in the row (aria-labelledby), unless the control already has a name of its own. A short row is a grid (settings.css, .st-row.st-short):
 * `under` lines (the cap chip, the help) come after the control and span both columns, so they never set the label column's width. */
function rowOf(text: HTMLElement, label: Node, controls: readonly Node[], ...under: (Node | null)[]): HTMLElement {
  if (!text.id) text.id = nextId();
  for (const c of controls) {
    if (c instanceof HTMLElement && c.matches("input, select, textarea, button") && !namesItself(c)) {
      c.setAttribute("aria-labelledby", text.id);
    }
  }
  // A pop-up with no width of its own is as wide as its option: its control is content-sized, so the row stacks only when they do not fit (settings.css, .st-control.st-picker).
  const picker = controls.some((c) => c instanceof HTMLSelectElement && c.style.width === "");
  return h("div", { class: shortRow(controls) ? "st-row st-short" : "st-row" }, label, h("div", { class: picker ? "st-control st-picker" : "st-control" }, ...controls), ...under);
}

/** A control with a name of its own keeps it: an aria-label, an aria-labelledby (switchRow's), or a button's text. A select's options are not its name. */
function namesItself(c: HTMLElement): boolean {
  if (c.hasAttribute("aria-label") || c.hasAttribute("aria-labelledby")) return true;
  return c.matches("button") && (c.textContent ?? "").trim() !== "";
}

export interface SwitchRow { el: HTMLElement; set(on: boolean, o?: { chip?: string | null; disabled?: boolean }): void }

/** A switch row. The label toggles it too. A chip says what is missing: it sits under the label, as a line of its own that spans the row (so it reads as this row's and never as the row
 * above's, at every width, and never sets the label's width). `set` changes the switch in place, so focus stays. */
export function switchRow(label: string, o: { on: boolean; onChange: (v: boolean) => void; help?: string; chip?: string | null; disabled?: boolean }): SwitchRow {
  let on = o.on;
  const chipSlot = h("span", { class: "st-chipslot st-under" });
  const sw = h("button", { class: "switch", type: "button" });
  const text = h("span", { class: "st-labeltext", text: label });
  // The switch is named by its label: a button with no text of its own would otherwise have no name.
  if (!text.id) text.id = nextId();
  sw.setAttribute("aria-labelledby", text.id);
  const helpLine = o.help ? h("div", { class: "st-under" }, help(o.help)) : null;
  const labelBlock = h("div", { class: "st-label" }, text);
  const el = rowOf(text, labelBlock, [sw], chipSlot, helpLine);
  const set = (next: boolean, p: { chip?: string | null; disabled?: boolean } = {}): void => {
    on = next;
    sw.classList.toggle("on", on);
    sw.setAttribute("aria-pressed", String(on));
    if (p.disabled !== undefined) {
      sw.disabled = p.disabled;
      // The dim covers the label and its help line; the chip stays as readable as ever (it is the reason the switch is off).
      text.classList.toggle("st-disabled", p.disabled);
      helpLine?.classList.toggle("st-disabled", p.disabled);
    }
    if (p.chip !== undefined) {
      clear(chipSlot);
      if (p.chip) chipSlot.append(chip(p.chip));
    }
  };
  sw.addEventListener("click", () => {
    if (sw.disabled) return;
    const next = !on;
    set(next);
    o.onChange(next);
  });
  // A click on the label or its help toggles the switch. The chip is a sibling of both, not inside either, so a click on it never reaches this handler: it is a word, not a label.
  const fromLabel = (): void => sw.click();
  labelBlock.addEventListener("click", fromLabel);
  helpLine?.addEventListener("click", fromLabel);
  set(o.on, { chip: o.chip ?? null, disabled: o.disabled ?? false });
  return { el, set };
}

/** A key or URL field: a password field unless `secure` is false, showing what was typed (the draft), never a stored value. */
export function keyField(o: { id: string; drafts: DraftBook; placeholder: string; secure?: boolean; disabled?: boolean; onInput: () => void }): HTMLInputElement {
  const input = h("input", { class: "st-keyfield", type: o.secure === false ? "text" : "password", autocomplete: "off", spellcheck: "false", placeholder: o.placeholder });
  input.value = o.drafts.text(o.id);
  // A field the store cannot be read for is disabled but still shows its held draft: nothing can be typed or written until the store answers.
  if (o.disabled) {
    input.disabled = true;
    return input;
  }
  input.addEventListener("input", () => {
    o.drafts.edit(o.id, input.value);
    o.onInput();
  });
  return input;
}

/** "Check again" for a key the store could not be read for: asks once more, sets the answer (a typed draft is kept), runs `onPresent` when the key is now stored, then repaints.
 * Not a primary button. `label` names the key for a screen reader ("Check again: Resend API key"), since two such buttons can share a card. */
export function checkAgain(ctx: SettingsCtx, id: string, repaint: () => void, onPresent?: () => unknown, label?: string): HTMLButtonElement {
  const check = button("Check again", () => {
    // A read that rejects is no answer: the store is taken as unreadable, never as absent.
    void ctx.backend.secretPresence(id).catch((): Presence => "unreadable").then(async (p) => {
      ctx.drafts.setPresence(id, p);
      // The answer shows at once (the field and its words), then the models are fetched, then the card is drawn with the result.
      repaint();
      if (p === "present" && onPresent) await onPresent();
      repaint();
    });
  });
  if (label) check.setAttribute("aria-label", `Check again: ${label}`);
  return check;
}

/** A status: a dot and one short phrase, never wrapped inside. The dot's colour comes from the phrase (status.ts). */
export function chip(text: string): HTMLElement {
  return h("span", { class: `st-chip st-${tone(text)}`, text });
}

/** Buttons and chips in a group: on one line when they fit, on as many lines as needed otherwise. */
export function wrapRow(...children: Node[]): HTMLElement {
  return h("div", { class: "st-wrap" }, ...children);
}

/** "Show path" reveals the paths, each with a Copy button. `shown` is what is drawn, `path` is what Copy puts on the clipboard. A Copy says "Copied" or "Couldn't copy" until the
 * paths are shown or hidden again (no timer). */
export function pathDisclosure(lines: readonly { label: string; path: string; shown: string }[], copy: (text: string) => Promise<boolean>): HTMLElement {
  const bodyId = nextId();
  const copies: HTMLButtonElement[] = [];
  const body = h("div", { class: "st-paths", id: bodyId, hidden: true },
    ...lines.map((l) => {
      const b = button("Copy", () => {
        const said = (ok: boolean) => { b.textContent = ok ? "Copied" : "Couldn't copy"; };
        copy(l.path).then(said, () => said(false));
      });
      copies.push(b);
      return h("div", { class: "st-pathline" },
        h("span", { class: "st-pathlabel", text: l.label }),
        h("span", { class: "st-path", text: l.shown }),
        b,
      );
    }),
  );
  const toggle = button("Show path", () => {
    body.hidden = !body.hidden;
    for (const c of copies) c.textContent = "Copy";
    toggle.textContent = body.hidden ? "Show path" : "Hide path";
    toggle.setAttribute("aria-expanded", String(!body.hidden));
  });
  toggle.setAttribute("aria-expanded", "false");
  toggle.setAttribute("aria-controls", bodyId);
  return h("div", { class: "st-pathbox" }, wrapRow(toggle), body);
}

/** A line of help under a label or a card: 12 pt, and `warn` makes it amber. */
export function help(text: string, warn = false): HTMLElement {
  return h("div", { class: warn ? "hint warn" : "hint", text });
}

export function notice(kind: "ok" | "err" | "warn", text: string): HTMLElement {
  return h("div", { class: `notice ${kind}`, text });
}

export function button(text: string, onclick: () => void, kind?: "primary" | "danger"): HTMLButtonElement {
  return h("button", { type: "button", class: kind, onclick, text });
}

/** A pop-up menu with the window's own field look. */
export function select(options: readonly (readonly [string, string])[], value: string, onChange: (v: string) => void): HTMLSelectElement {
  const el = h("select", { onchange: () => onChange(el.value) });
  for (const [v, label] of options) el.append(h("option", { value: v, text: label }));
  el.value = value;
  return el;
}

/** The control whose refused save is being reverted, while `forceValues` runs: setValue writes that one even though it is in use. Null otherwise. */
let forcedFor: Element | null = null;

/** Runs `fn` so that setValue writes `only` (the control whose save was refused) even while it is in use. Every other field keeps what the person typed. Used only for a revert (app.ts). */
export function forceValues(fn: () => void, only: Element | null): void {
  const was = forcedFor;
  forcedFor = only;
  try { fn(); } finally { forcedFor = was; }
}

/** Writes a value into a field only when the person is not typing in it, so a slider mid-drag or a field being typed in is never reset. */
export function setValue(el: HTMLInputElement | HTMLSelectElement, value: string): void {
  if ((el === forcedFor || el !== document.activeElement) && el.value !== value) el.value = value;
}

/** A refused save's note, at the top of the card the control is in: one `.st-cardnote` notice, replaced by the next note and removed by clearCardNote. */
export function cardNote(card: HTMLElement, text: string): void {
  clearCardNote(card);
  const note = notice("err", text);
  note.classList.add("st-cardnote");
  // Inserted after the failure, so an alert is read out when it lands.
  note.setAttribute("role", "alert");
  const head = card.querySelector(":scope > .st-cardhead");
  if (head) head.after(note);
  else card.prepend(note);
}

export function clearCardNote(card: HTMLElement | null): void {
  card?.querySelector(":scope > .st-cardnote")?.remove();
}

export function details(summary: string, ...children: Node[]): HTMLDetailsElement {
  return h("details", { class: "st-details" }, h("summary", { text: summary }), ...children);
}

/** A diff preview: one line per row, added green, removed red, the rest dim. */
export function renderDiff(text: string): HTMLElement {
  const box = h("div", { class: "diff" });
  for (const line of text.split("\n")) {
    const cls = line.startsWith("+") ? "add" : line.startsWith("-") ? "del" : "ctx";
    box.append(h("div", { class: cls, text: line }));
  }
  return box;
}

/** The tab bar: text tabs, the selected one underlined. When the labels do not fit the column it shows a pop-up menu instead (the only fallback; the labels are never shortened). */
export function tabBar(list: readonly Tab[], selected: Tab, onSelect: (t: Tab) => void): { el: HTMLElement; fit(): void; narrow(): boolean } {
  const row = h("div", { class: "st-tabs", role: "tablist" },
    ...list.map((t) => h("button", { type: "button", role: "tab", "aria-selected": String(t === selected), onclick: () => onSelect(t), text: tabTitle(t) })),
  );
  const menu = select(list.map((t) => [t, tabTitle(t)] as const), selected, (v) => onSelect(v as Tab));
  menu.classList.add("st-tabmenu");
  menu.setAttribute("aria-label", "Tab");
  const el = h("div", { class: "st-tabbar" }, row, menu);
  // The row keeps its layout when it turns narrow (visibility only), so its own width still tells whether the labels fit.
  const fit = (): void => {
    el.classList.toggle("narrow", row.scrollWidth > row.clientWidth);
  };
  // Narrow: the menu stands in for the buttons (CSS hides the row by visibility, so its own box still reports the buttons).
  return { el, fit, narrow: () => el.classList.contains("narrow") };
}
