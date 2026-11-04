// The Settings window's shell (Settings restyle, "The window"): the sidebar of the six pages and the detail area with the page's title, its tab bar and its one column. The
// collapsed sidebar is CSS (the breakpoint is layout.ts's BREAKPOINT); the only listener is one window resize, which fits the tab bar once per burst of frames. Storage is read and
// written through try, so a blocked store still opens the window (General, the first tab).

import { h, clear, svg } from "../views/dom";
import { PAGES, pageTitle, pageColor, tabs, tabKey, migrate, placeWithStored, focusAfter, focusTarget, SECTION_KEY, type Page, type Place } from "./route.ts";
import { PAGE_ICONS } from "./icons.ts";
import { button, card, notice, tabBar, wrapRow } from "./kit.ts";
import type { PageView } from "./ctx.ts";

/** The page-level strip's words: a notice of one kind, with the buttons that answer it. The strip is cleared by a page change; a pinned one (the boot's problem) is not. */
export interface Banner { text: string; kind?: "ok" | "err" | "warn"; actions?: { label: string; onClick: () => void }[] }

export function buildShell(o: {
  version: string; build: (place: Place) => PageView;
  storage: Pick<Storage, "getItem" | "setItem"> | null; initial?: Place | null;
}): { el: HTMLElement; select(place: Place): void; sync(): void; current(): Place; banner(b: Banner | null): void; pin(b: Banner | null): void; fit(): void } {
  const read = (key: string): string | null => {
    try { return o.storage?.getItem(key) ?? null; } catch { return null; }
  };
  const write = (key: string, value: string): void => {
    try { o.storage?.setItem(key, value); } catch { /* a blocked store keeps no place: the window still works */ }
  };
  // A place with no tab opens on the tab stored for its page (placeWithStored), else on the page's first.
  let current: Place = placeWithStored(o.initial ?? migrate(read(SECTION_KEY)), read);
  let view: PageView | null = null;
  let bar: { el: HTMLElement; fit(): void; narrow(): boolean } | null = null;
  let frame = 0;

  const navs = new Map<Page, HTMLButtonElement>();
  const nav = h("nav", { class: "st-side", "aria-label": "Settings pages" },
    h("div", { class: "st-head" },
      h("span", { class: "st-appname", text: "NotchMeow" }),
      h("span", { class: "st-version", text: o.version }),
    ),
    ...PAGES.map((page) => {
      const b = h("button", {
        class: "st-nav", type: "button", "aria-label": pageTitle(page), title: pageTitle(page),
        onclick: () => select({ page, tab: null }),
      },
      h("span", { class: "st-tile", style: `background:${pageColor(page)}` }, svg(PAGE_ICONS[page], 14)),
      h("span", { class: "st-navlabel", text: pageTitle(page) }),
      );
      navs.set(page, b);
      return b;
    }),
  );
  const title = h("h1", { class: "st-title" });
  const tabHost = h("div", { class: "st-tabhost" });
  // The pinned strip is the window's own problem (the settings file could not be read at boot): above the page strip, and only its own buttons take it away.
  // Both are alerts: a note put in after a failure is read out as it lands.
  const pinned = h("div", { class: "st-strip", hidden: true, role: "alert" });
  const strip = h("div", { class: "st-strip", hidden: true, role: "alert" });
  const scroll = h("div", { class: "st-scroll" });
  const el = h("div", { class: "st-shell" },
    nav,
    h("main", { class: "st-detail" }, h("div", { class: "st-top" }, title, tabHost), pinned, strip, scroll),
  );

  function fill(host: HTMLElement, b: Banner | null): void {
    clear(host);
    host.hidden = !b;
    if (!b) return;
    host.append(notice(b.kind ?? "err", b.text));
    if (b.actions?.length) host.append(wrapRow(...b.actions.map((a) => button(a.label, a.onClick))));
  }

  /** The page-level strip, above the column: what a page could not say in its own card. A page change clears it (select). */
  function banner(b: Banner | null): void {
    fill(strip, b);
  }

  /** The pinned strip: stays until its own buttons take it away; a page change does not touch it. */
  function pin(b: Banner | null): void {
    fill(pinned, b);
  }

  /** The sidebar's selection, the title and the tab bar for the current place. */
  function paint(): void {
    for (const [page, b] of navs) {
      if (page === current.page) b.setAttribute("aria-current", "page");
      else b.removeAttribute("aria-current");
    }
    title.textContent = pageTitle(current.page);
    clear(tabHost);
    bar = null;
    const list = tabs(current.page);
    if (current.tab && list.length > 0) {
      const page = current.page;
      bar = tabBar(list, current.tab, (t) => select({ page, tab: t }));
      tabHost.append(bar.el);
    }
  }

  /** The sidebar or tab button the focus is on now, read before the page is rebuilt (a rebuild takes the focus with the old buttons). */
  function focusedKind(): "nav" | "tab" | null {
    const el = document.activeElement;
    if (!(el instanceof HTMLElement)) return null;
    if (el.closest(".st-nav")) return "nav";
    if (el.closest(".st-tabbar")) return "tab";
    return null;
  }

  function select(place: Place): void {
    const was = focusedKind();
    view?.dispose?.();
    banner(null);
    current = placeWithStored(place, read);
    try {
      view = o.build(current);
    } catch (err) {
      // The old page is already gone (disposed above), so the place stays and the page says what happened; the sidebar and the tabs still work.
      console.error("[notchmeow] settings page failed to build", err);
      view = { el: card("This page couldn't be drawn.", null) };
    }
    clear(scroll);
    scroll.append(h("div", { class: "st-column" }, view.el));
    write(SECTION_KEY, current.page);
    if (current.tab) write(tabKey(current.page), current.tab);
    paint();
    bar?.fit();
    // A choice made from the keyboard keeps the focus: on the new sidebar button, or on the new tab (the narrow window's tab menu when the tabs are hidden).
    const to = focusAfter(was, current);
    if (to === "nav") navs.get(current.page)?.focus();
    else if (to === "tab" && bar) {
      // The narrow state is the tab bar's own (fit() decided it just above), not a layout read: the buttons are only hidden by visibility.
      const target = focusTarget(bar.narrow());
      const control = target === "menu" ? bar.el.querySelector<HTMLElement>("select.st-tabmenu") : bar.el.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]');
      control?.focus();
    }
  }

  // One listener for the window's width: a frame per burst of resizes, and the tab bar decides again whether its labels fit.
  window.addEventListener("resize", () => {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      bar?.fit();
    });
  });

  select(current);
  // The first measure needs the shell in the page, which the caller mounts after this returns.
  requestAnimationFrame(() => bar?.fit());

  return { el, select, sync: () => view?.sync?.(), current: () => current, banner, pin, fit: () => bar?.fit() };
}
