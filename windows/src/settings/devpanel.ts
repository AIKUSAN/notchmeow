// Dev server only (Settings restyle, Task 5): the sample frame the owner's pictures are cut from (`settings.html?shot=<width>`, one iframe at the top left, its width written
// to <output id="frame-width"> so the render script can check it) and the `?dev` page's Settings panel, which shows the window at three widths side by side.
// Only the dev server loads this file (cat/dev.ts and main.ts check import.meta.env.DEV).

import { h, clear } from "../views/dom";
import { button, row, select, wrapRow } from "./kit.ts";
import { PAGES, pageTitle, tabs, tabTitle, type Page, type Tab } from "./route.ts";

/** One iframe at (0, 0) of the page, `width` by `height`. Same origin, so the page can read the frame's width once it has loaded. */
export function mountShotFrame(root: HTMLElement, width: number, height: number, src: string): void {
  clear(root);
  document.body.style.margin = "0";
  root.style.cssText = "padding:0;margin:0;max-width:none;";
  const frame = h("iframe", { src, width: String(width), height: String(height), style: "display:block;border:0" });
  frame.addEventListener("load", () => {
    root.append(h("output", { id: "frame-width", text: String(frame.contentWindow?.innerWidth ?? 0) }));
  });
  // The frame's layout check (reportLayout) cannot be read from outside the frame, so the frame posts it here and this page writes it where --dump-dom can read it.
  window.addEventListener("message", (e: MessageEvent) => {
    if (e.source !== frame.contentWindow || typeof e.data?.layoutCheck !== "string") return;
    root.append(h("output", { id: "layout-check", hidden: true, text: e.data.layoutCheck }));
  });
  root.append(frame);
}


/** The text the stress check gives the first short row's label: long enough to wrap at 415 px, with ordinary words and one unbreakable 46-character word (it must wrap by its letters, never overflow). */
const LONG_LABEL = "Show every agent session you run on this computer, including AgentSessionLogsOnThisComputerForEveryAgentRun and the long ones that need a second line";

/** The boxes of an element's own text, one per text fragment (a status dot is an element, not text, so it is not a line of its own). Whitespace-only nodes are skipped. */
function textRects(el: Element | null | undefined): DOMRect[] {
  if (!el) return [];
  const out: DOMRect[] = [];
  const range = document.createRange();
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!(n.textContent ?? "").trim()) continue;
    range.selectNodeContents(n);
    out.push(...Array.from(range.getClientRects()));
  }
  return out;
}

/** The width the label's text takes on one line: the wrap point is not its width, so the label is measured with no wrap (and the style put back). */
function naturalWidth(label: HTMLElement | null): number {
  if (!label) return 0;
  const before = label.style.whiteSpace;
  label.style.whiteSpace = "nowrap";
  const rects = textRects(label);
  label.style.whiteSpace = before;
  if (rects.length === 0) return 0;
  return Math.max(...rects.map((r) => r.right)) - Math.min(...rects.map((r) => r.left));
}

/** The layout check's measurement (`measure=switchrows`, render-free: scripts/check-settings-layout.sh). For every short row (a switch or a chip beside its label): the label's text
 * lines, the first line's box, the control's box, the label block's box and whether the row overflows. With `stress` the first row's label is made long, so the check sees it wrap. The
 * result goes to the page holding the frame, or into this page when it is the top one. */
export function reportLayout(root: HTMLElement, what: string, stress: boolean, forget = false): void {
  if (what !== "switchrows") return;
  if (stress) {
    // Probes inside the first card, so they have the card's room (about 289 px at 415), not the column's: a probe for the floor (a normal label beside a group of nowrap buttons, the widest control a short row takes). Its label must keep its floor and nothing may overflow.
    const probe = row("Repeated errors", wrapRow(button("Unmute", () => {}), button("Show me an example", () => {}), button("Choose kinds", () => {})));
    probe.dataset.probe = "1";
    (root.querySelector(".st-card") ?? root).append(probe);
    // A stacked probe: a label with one 46-character unbreakable word beside a select (not a short row), so it stacks. It must stay inside the 415 px window.
    const stacked = row("AgentSessionLogsOnThisComputerForEveryAgentRun", select([["a", "A"]], "a", () => {}));
    stacked.dataset.stacked = "1";
    (root.querySelector(".st-card") ?? root).append(stacked);
  }
  // `forget` (measure=switchrows&forget=1, stress): the long-named machine's Forget is pressed, so its confirm state (the danger button "Forget <name>?" and Keep) is measured.
  if (forget) {
    const long = Array.from(root.querySelectorAll<HTMLElement>("[data-machine]")).find((m) => (m.querySelector(".st-labeltext")?.textContent ?? "").length > 40);
    Array.from(long?.querySelectorAll<HTMLButtonElement>(".st-control button") ?? []).find((b) => b.textContent === "Forget")?.click();
  }
  // The measured rows are exactly the rule under test: the short rows kit.ts builds. A machine row (Devices) has its own measure below.
  const rows = Array.from(root.querySelectorAll<HTMLElement>(".st-row.st-short:not([data-machine])"));
  const firstLabel = rows[0]?.querySelector<HTMLElement>(".st-labeltext");
  if (stress && firstLabel) firstLabel.textContent = LONG_LABEL;
  const box = (el: Element | null | undefined) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, left: r.left, right: r.right };
  };
  const out = {
    width: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
    // The rows that are not kit rows (the Cat page's own .row lines): their right edge and overflow, so a wide control there is still caught.
    plain: Array.from(root.querySelectorAll<HTMLElement>(".row")).map((el) => ({ right: el.getBoundingClientRect().right, overflow: el.scrollWidth > el.clientWidth, width: el.getBoundingClientRect().width })),
    stacked: Array.from(root.querySelectorAll<HTMLElement>("[data-stacked]")).map((el) => ({ right: el.getBoundingClientRect().right, overflow: el.scrollWidth > el.clientWidth })),
    // Every row of the kit, short or not (a key field, a pop-up, a machine): its right edge and overflow, so no row can run past the window unmeasured.
    allRows: Array.from(root.querySelectorAll<HTMLElement>(".st-row")).map((r) => ({
      label: (r.querySelector(".st-labeltext")?.textContent ?? "").slice(0, 40),
      right: r.getBoundingClientRect().right,
      overflow: r.scrollWidth > r.clientWidth,
    })),
    // Devices' machine rows: the name's own text (not the status dot) by its lines and right edge, the state chip and the first button by their right edges, and the row's overflow.
    machines: Array.from(root.querySelectorAll<HTMLElement>("[data-machine]")).map((m) => {
      const label = m.querySelector(".st-labeltext");
      const pieces = textRects(label);
      const chip = m.querySelector<HTMLElement>(".st-chip")?.getBoundingClientRect();
      const buttons = Array.from(m.querySelectorAll<HTMLElement>(".st-control button")).map((b) => b.getBoundingClientRect());
      return {
        name: (label?.textContent ?? "").slice(0, 60),
        lines: new Set(pieces.map((r) => Math.round(r.top))).size,
        nameRight: pieces.length ? Math.max(...pieces.map((r) => r.right)) : 0,
        rowRight: m.getBoundingClientRect().right,
        chipRight: chip?.right ?? 0,
        chipWidth: chip?.width ?? 0,
        buttons: buttons.length,
        buttonRight: buttons.length ? Math.max(...buttons.map((b) => b.right)) : 0,
        buttonWidth: buttons[0]?.width ?? 0,
        overflow: m.scrollWidth > m.clientWidth,
      };
    }),
    // The help lines of the rows that are not short: each comes after its control in the document and below it (the Mac's order), and its right edge is in its row.
    helps: Array.from(root.querySelectorAll<HTMLElement>(".st-row:not(.st-short) > .st-under")).map((u) => {
      const row = u.parentElement;
      const control = row?.querySelector<HTMLElement>(".st-control");
      const controlBox = control?.getBoundingClientRect();
      const helpBox = u.getBoundingClientRect();
      return {
        label: (row?.querySelector(".st-labeltext")?.textContent ?? "").slice(0, 40),
        after: !!control && !!(control.compareDocumentPosition(u) & Node.DOCUMENT_POSITION_FOLLOWING),
        below: controlBox ? helpBox.top >= controlBox.bottom - 1 : false,
        helpRight: helpBox.right,
        rowRight: row?.getBoundingClientRect().right ?? 0,
        overflow: row ? row.scrollWidth > row.clientWidth : false,
      };
    }),
    // The pop-up menus (rows whose control is a select, not a short row): the select's box, whether it stacks under its label, and whether it is inside its card and its row.
    pickers: Array.from(root.querySelectorAll<HTMLElement>(".st-row:not(.st-short)")).flatMap((r) => {
      const sel = r.querySelector<HTMLElement>(".st-control select");
      if (!sel) return [];
      const box = sel.getBoundingClientRect();
      const card = r.closest(".st-card")?.getBoundingClientRect();
      // The label is the text's own box (its glyph rects), not the .st-label block: a help line inside the block would make the block as tall as the help.
      const text = textRects(r.querySelector<HTMLElement>(".st-labeltext"));
      const textBottom = text.length ? Math.max(...text.map((t) => t.bottom)) : 0;
      const under = r.querySelector<HTMLElement>(".st-under");
      return [{
        label: (r.querySelector(".st-labeltext")?.textContent ?? "").slice(0, 40),
        natural: naturalWidth(r.querySelector<HTMLElement>(".st-labeltext")),
        stacked: text.length ? box.top >= textBottom - 1 : false,
        gap: text.length ? box.top - textBottom : 0,
        // The row's help line comes after the select in the document (the Mac's order): false when there is none.
        underAfter: !!under && under.getBoundingClientRect().height > 0 && !!(sel.compareDocumentPosition(under) & Node.DOCUMENT_POSITION_FOLLOWING),
        select: { left: box.left, right: box.right, top: box.top, bottom: box.bottom },
        width: box.width,
        insideCard: card ? box.left >= card.left - 0.5 && box.right <= card.right + 0.5 : false,
        overflow: r.scrollWidth > r.clientWidth,
      }];
    }),
    rows: rows.map((row) => {
      const label = row.querySelector<HTMLElement>(".st-labeltext");
      const pieces = textRects(label);
      const lines = new Set(pieces.map((r) => Math.round(r.top))).size;
      const line = pieces[0];
      return {
        label: (label?.textContent ?? "").slice(0, 40),
        chip: row.querySelector(".st-chip")?.textContent ?? "",
        lines,
        first: line ? { top: line.top, bottom: line.bottom } : null,
        control: box(row.querySelector(".st-control")),
        block: box(label?.parentElement),
        labelWidth: label?.parentElement?.getBoundingClientRect().width ?? 0,
        natural: naturalWidth(label),
        controlWidth: row.querySelector(".st-control")?.getBoundingClientRect().width ?? 0,
        em: label ? parseFloat(getComputedStyle(label).fontSize) : 0,
        probe: row.dataset.probe === "1",
        overflow: row.scrollWidth > row.clientWidth,
      };
    }),
  };
  postLayout(root, JSON.stringify(out));
}

/** The layout check's result goes to the page holding the frame, or into this page when it is the top one (where --dump-dom reads it). */
function postLayout(root: HTMLElement, json: string): void {
  if (window.parent !== window) window.parent.postMessage({ layoutCheck: json }, location.origin);
  else root.append(h("output", { id: "layout-check", hidden: true, text: json }));
}

/** The keyboard check (`measure=tabfocus`, scripts/check-settings-layout.sh): a tab chosen from the keyboard leaves the focus where the tab bar says. Narrow, the buttons are
 * hidden, so the keyboard reaches the tab menu: its value changes and the change is the choice. Wide, the tab button is focused and clicked. The result is what has the focus
 * after the choice, and whether the bar is narrow. */
export function reportTabFocus(root: HTMLElement): void {
  // Narrow is decided here by the tab bar's own test (fit(): the row's labels overflow), read now and not from the class: a frame that is not painted (a window in the
  // background) has not run the shell's fit yet. The choice's select() runs fit() before it moves the focus, so the page's own state decides where the focus goes.
  const row = root.querySelector<HTMLElement>(".st-tabs");
  const narrow = row ? row.scrollWidth > row.clientWidth : false;
  const menu = root.querySelector<HTMLSelectElement>("select.st-tabmenu");
  const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('[role="tab"]'));
  let chosen: "menu" | "tab" | null = null;
  if (narrow && menu) {
    const other = Array.from(menu.options).find((o) => !o.selected);
    if (other) {
      menu.focus();
      menu.value = other.value;
      menu.dispatchEvent(new Event("change"));
      chosen = "menu";
    }
  } else {
    const other = buttons.find((b) => b.getAttribute("aria-selected") !== "true");
    if (other) {
      other.focus();
      other.click();
      chosen = "tab";
    }
  }
  const active = document.activeElement as HTMLElement | null;
  postLayout(root, JSON.stringify({
    width: window.innerWidth,
    narrow,
    chosen,
    focusedTag: active?.tagName ?? "",
    focusedRole: active?.getAttribute("role") ?? "",
    focusedSelected: active?.getAttribute("aria-selected") ?? "",
  }));
}

const WIDTHS = [415, 720, 1100] as const;
const STATES = ["ready", "empty", "error"] as const;
const THEMES = ["dark", "light"] as const;

/** The places a picture can show: each page, and each of its tabs. */
function places(): { value: string; label: string }[] {
  const out: { value: string; label: string }[] = [];
  for (const page of PAGES as readonly Page[]) {
    out.push({ value: page, label: pageTitle(page) });
    for (const tab of tabs(page) as Tab[]) out.push({ value: `${page}/${tab}`, label: `${pageTitle(page)}: ${tabTitle(tab)}` });
  }
  return out;
}

/** The sample's address for one place and its settings. */
function srcFor(place: string, state: string, stress: boolean, theme: string): string {
  const [page, tab] = place.split("/");
  const q = new URLSearchParams({ sample: state, page });
  if (tab) q.set("tab", tab);
  if (stress) q.set("stress", "");
  q.set("theme", theme);
  return `/settings.html?${q.toString()}`;
}

/** The Settings panel of the `?dev` page: a place, a state, stress, a theme and a height, and three frames at 415, 720 and 1100 px. */
export function mountSettingsDev(root: HTMLElement, before: Node | null): void {
  const section = h("section", { id: "settings-dev", style: "margin:16px 0;color:inherit;font:13px system-ui,sans-serif" });
  const frames: HTMLIFrameElement[] = [];
  let place = "general";
  let state: string = STATES[0];
  let stress = false;
  let theme: string = THEMES[0];
  let height = 600;
  const refresh = (): void => {
    for (const f of frames) f.src = srcFor(place, state, stress, theme);
  };
  const field = (label: string, control: HTMLElement): HTMLElement => h("label", { style: "display:inline-flex;gap:6px;align-items:center;margin-right:12px" }, label, control);
  const placeSel = h("select", { onchange: (e: Event) => { place = (e.target as HTMLSelectElement).value; refresh(); } },
    ...places().map((p) => h("option", { value: p.value, text: p.label })));
  const stateSel = h("select", { onchange: (e: Event) => { state = (e.target as HTMLSelectElement).value; refresh(); } },
    ...STATES.map((s) => h("option", { value: s, text: s })));
  const themeSel = h("select", { onchange: (e: Event) => { theme = (e.target as HTMLSelectElement).value; refresh(); } },
    ...THEMES.map((t) => h("option", { value: t, text: t })));
  const stressBox = h("input", { type: "checkbox", onchange: (e: Event) => { stress = (e.target as HTMLInputElement).checked; refresh(); } });
  const heightBox = h("input", { type: "number", value: String(height), min: "200", step: "20", style: "width:80px", onchange: (e: Event) => {
    height = Number((e.target as HTMLInputElement).value) || height;
    for (const f of frames) f.height = String(height);
  } });
  const row = h("div", { style: "margin-bottom:10px" }, field("Place", placeSel), field("State", stateSel), field("Theme", themeSel), field("Stress", stressBox), field("Height", heightBox));
  const shelf = h("div", { style: "display:flex;gap:12px;align-items:flex-start;overflow-x:auto" });
  for (const w of WIDTHS) {
    const frame = h("iframe", { src: srcFor(place, state, stress, theme), width: String(w), height: String(height), style: "border:0;outline:1px solid currentColor;flex:0 0 auto" });
    frames.push(frame);
    shelf.append(h("div", { style: "flex:0 0 auto" }, h("div", { style: "margin-bottom:4px", text: `${w} px` }), frame));
  }
  clear(section);
  section.append(h("h2", { style: "font:600 15px system-ui,sans-serif;margin-bottom:8px", text: "Settings window" }), row, shelf);
  root.insertBefore(section, before);
}
