// The Settings window's pages and tabs, and how a stored section maps to one of them (the Settings restyle spec, rule 9: `settingsSection` keeps working, `settingsTab.<page>` is
// the only new key). Port of NotchBuddy/Sources/App/SettingsRoute.swift. Pure: no DOM, no storage, no clock. Tests: windows/scripts/settings-tests (check:settings).

export type Page = "general" | "agents" | "chat" | "services" | "cat" | "devices";
export type Tab = "general" | "shortcuts" | "yourai" | "keys" | "localmodels" | "sidekick" | "companion" | "look" | "outfits" | "personality" | "agentcats";
export interface Place { page: Page; tab: Tab | null }

/** The sidebar's order. */
export const PAGES: readonly Page[] = ["general", "agents", "chat", "services", "cat", "devices"];
/** The Companion tab (F3a): shown on Windows and Linux as on the Mac (Task 12). */
export const COMPANION_TAB_SHOWN = true;
/** No global shortcuts on Windows and Linux, so the Shortcuts tab stays out. */
export const SHORTCUTS_TAB_SHOWN = false;
export const SECTION_KEY = "settingsSection";

const TITLES: Record<Page, string> = { general: "General", agents: "Agents", chat: "AI and chat", services: "Services", cat: "Cat", devices: "Devices" };
const TAB_TITLES: Record<Tab, string> = {
  general: "General", shortcuts: "Shortcuts", yourai: "Your AI", keys: "Keys", localmodels: "Local models", sidekick: "Sidekick", companion: "Companion",
  look: "Look", outfits: "Outfits", personality: "Personality", agentcats: "Agents' cats",
};
const COLORS: Record<Page, string> = { general: "#8E939C", agents: "#3B9EFF", chat: "#E07950", services: "#7C5CFF", cat: "#D9A066", devices: "#5B8DEF" };

export const tabKey = (page: Page): string => `settingsTab.${page}`;
export const pageTitle = (page: Page): string => TITLES[page];
export const tabTitle = (tab: Tab): string => TAB_TITLES[tab];
export const pageColor = (page: Page): string => COLORS[page];

/** The places whose page holds text the user may have typed and not saved (a key field, a custom server's address). A window that hides builds them again so that text goes. */
export function holdsTypedText(place: Place): boolean {
  return place.page === "services" || (place.page === "chat" && (place.tab === "keys" || place.tab === "localmodels"));
}

/** The tabs a page shows, in order. Agents, Services and Devices have none. */
export function tabs(page: Page, opts: { companion?: boolean; shortcuts?: boolean } = {}): Tab[] {
  const companion = opts.companion ?? COMPANION_TAB_SHOWN;
  const shortcuts = opts.shortcuts ?? SHORTCUTS_TAB_SHOWN;
  switch (page) {
    case "general": return shortcuts ? ["general", "shortcuts"] : [];
    case "chat": return companion ? ["yourai", "keys", "localmodels", "sidekick", "companion"] : ["yourai", "keys", "localmodels", "sidekick"];
    case "cat": return ["look", "outfits", "personality", "agentcats"];
    default: return [];
  }
}

const isPage = (s: string): s is Page => (PAGES as readonly string[]).includes(s);
const isShownTab = (page: Page, s: string): s is Tab => (tabs(page) as string[]).includes(s);
const general = (): Place => ({ page: "general", tab: null });

/** The four old section tags, each with its place. The Shortcuts tag names its tab only where that tab is shown. migrate() and placeOrCurrent() both read this one table. */
const LEGACY: Readonly<Record<string, () => Place>> = {
  activepills: general,
  integrations: () => ({ page: "services", tab: null }),
  shortcuts: () => (isShownTab("general", "shortcuts") ? { page: "general", tab: "shortcuts" } : general()),
  sidekick: () => ({ page: "chat", tab: "sidekick" }),
};
const isLegacy = (s: string): boolean => Object.prototype.hasOwnProperty.call(LEGACY, s);

/** The place an old or new stored section names. An old tag gives its place; a bare page gives that page; `<page>/<tab>` gives that tab when the page shows it (a hidden or
 * unknown tab gives the page); anything else, a malformed path included, is General. */
export function migrate(stored: string | null | undefined): Place {
  if (stored == null) return general();
  if (isLegacy(stored)) return LEGACY[stored]();
  const parts = stored.split("/");
  if (!isPage(parts[0])) return general();
  const page = parts[0];
  if (parts.length === 1) return { page, tab: null };
  if (parts.length > 2 || parts[1] === "") return general();
  return { page, tab: isShownTab(page, parts[1]) ? parts[1] : null };
}

/** The tab to show on a page: the stored one when the page shows it, else its first tab; null for a page without tabs. */
export function tabFor(page: Page, stored: string | null | undefined): Tab | null {
  const visible = tabs(page);
  if (stored && (visible as string[]).includes(stored)) return stored as Tab;
  return visible[0] ?? null;
}

/** A place with its tab settled: a bare page takes the tab stored for it (`settingsTab.<page>`, read through the caller's own storage), a named tab stays when the page
 * shows it, and anything else gets the page's first tab. Pure: the storage is passed in. */
export function placeWithStored(place: Place, read: (key: string) => string | null | undefined): Place {
  return { page: place.page, tab: tabFor(place.page, place.tab ?? read(tabKey(place.page))) };
}

/** The shape the island's place word has (lib.rs's settings_place): lower-case words, at most one slash. */
const WELL_FORMED = /^[a-z]+(\/[a-z]+)?$/;

/** The place a `settings-place` event names. A well-formed word whose page is unknown (`zzz`) keeps the page on screen; anything else reads through migrate. */
export function placeOrCurrent(raw: string | null | undefined, current: Place): Place {
  const unknown = raw != null && WELL_FORMED.test(raw) && !isPage(raw.split("/")[0]) && !isLegacy(raw);
  return unknown ? current : migrate(raw);
}

/** Whether a place is the page already on screen: a bare page is shown when its page is, a named tab only when that tab is. A place shown already is not rebuilt. */
export function alreadyShown(place: Place, current: Place): boolean {
  return place.page === current.page && (place.tab === null || place.tab === current.tab);
}

/** The control that takes the focus after a tab is chosen from the keyboard: the tab menu when the tab bar is narrow (the buttons are hidden then), else the selected tab. */
export function focusTarget(narrow: boolean): "tab" | "menu" {
  return narrow ? "menu" : "tab";
}

/** Where keyboard focus goes once a page or a tab has been chosen from a sidebar or tab button: the new sidebar button (`nav`), the new tab (`tab`), or nowhere (null) when
 * the focus was on neither. A page with no tabs has no tab to take it, so the sidebar button does. */
export function focusAfter(was: "nav" | "tab" | null, place: Place): "nav" | "tab" | null {
  if (was === null) return null;
  return was === "tab" && place.tab !== null ? "tab" : "nav";
}
