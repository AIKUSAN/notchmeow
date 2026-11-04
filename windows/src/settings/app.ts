// The Settings window's app (Settings restyle, "The window" and "The swap"): listens for the window's events, boots the backend, loads which keys are saved (never their values),
// builds the context every page reads and mounts the shell. The listeners are registered before the first await, so an event sent during boot is not missed. The real window
// and the dev routes both start here; the six pages are built below, and main.ts only chooses the backend.
// General, Devices (Task 8), the chat's three AI tabs (Task 9), and the Sidekick tab and the Cat tabs (Task 10) are built. Tasks 9 and 10 were the last two pages.

import { buildShell } from "./shell.ts";
import { bannerText, bootState, type BootBanner } from "./bootstate.ts";
import { cardNote, clearCardNote, forceValues } from "./kit.ts";
import { makeSaver, tidyEcho } from "./savestate.ts";
import type { SettingsBackend } from "./backend.ts";
import type { PageView, SettingsCtx } from "./ctx.ts";
import { DraftBook } from "./drafts.ts";
import type { Presence } from "./status.ts";
import { alreadyShown, holdsTypedText, migrate, placeOrCurrent, type Place } from "./route.ts";
import { hold, reconcile, released, type Held } from "./held.ts";
import { devicesSection, platformOf } from "./devices.ts";
import { agentsPage } from "./agents.ts";
import { servicesPage } from "./services.ts";
import { generalPage } from "./general.ts";
import { yourAiTab, keysTab, localModelsTab } from "./ai.ts";
import { sidekickSection } from "./sidekick";
import { companionTab } from "./companion.ts";
import { brainNameOf } from "./companionrules.ts";
import { catSection, type CatTab } from "./cat";
import { AiCache } from "./aicache.ts";
import { CLOUD_PROVIDERS, IS_TAURI, type AiServer } from "../core/bridge.ts";
import { DEFAULT_SETTINGS, type Settings } from "../core/state.ts";
import { cleanCatBlock } from "../cat/display";
import { cleanSidekickSettings } from "../sidekick/core.ts";
import type { LiveProject } from "../projects/present.ts";

/** The eleven keys whose presence the window loads. A saved key shows as saved; its value never reaches the page. */
const KEYS = [
  "anthropic-api-key", "google-api-key", "openai-api-key",
  "stripe-api-key", "github-token", "vercel-token",
  "n8n-url", "n8n-api-key", "resend-api-key", "notion-api-key", "calcom-api-key",
] as const;

const GNOME_NOTE = "On this system the desktop decides where the cat's window goes: it lands where the system puts it and may not keep its spot between runs; you can drag it from there.";

/** The clean-up the window gives the settings it holds: the cat block and the sidekick object. It runs at boot and on every change from the island. */
const tidy = (s: Settings): Settings => ({ ...s, cat: cleanCatBlock(s.cat), sidekick: cleanSidekickSettings(s.sidekick) });

/** The island's live projects as the window holds them: only a folder name and a name, both text. Anything else in the message is dropped (never a path). */
function namesOf(list: unknown): LiveProject[] {
  if (!Array.isArray(list)) return [];
  const out: LiveProject[] = [];
  for (const p of list as Partial<LiveProject>[]) {
    if (p !== null && typeof p === "object" && typeof p.catKey === "string" && typeof p.name === "string") out.push({ catKey: p.catKey, name: p.name });
  }
  return out;
}

/** `typed` is for the dev samples only: the text a field starts with (a draft typed and not saved). The app never passes it. */
export async function startSettingsApp(root: HTMLElement, backend: SettingsBackend, o: { initial?: Place | null; storage: Pick<Storage, "getItem" | "setItem"> | null; typed?: Readonly<Record<string, string>> }): Promise<void> {
  let pending = null as Place | null;
  let shell = null as ReturnType<typeof buildShell> | null;
  let drafts = null as DraftBook | null;
  let settings: Settings = { ...DEFAULT_SETTINGS };
  // The card that holds the current "Couldn't save." note, so a later confirmed save or a page change can take it away.
  let noteCard: HTMLElement | null = null;
  // The window starts hidden at launch, so it is away until it is focused: a page built at boot does not look for the AI and chat on a window nobody sees.
  // A headless dev picture has no focus, so the dev sample's flag (main.ts) counts as seen; the real window is away until it has focus.
  let away = !document.hasFocus() && document.documentElement.dataset.shot !== "1";
  // The boot snapshot is applied after its awaits. An island change that arrives before then is kept here and wins over the snapshot.
  let booted = false;
  let early: Partial<Settings> = {};
  // Whether the chat page is open. Declared here, before the first await, so an event during boot reads it safely.
  let chatOpen = false;
  // The Devices section, while it is built: the hide puts its Name back.
  let devicesView: { reset(): void } | null = null;
  // The cache is built before the first await: the servers' event can arrive during boot, and it is read through the saved keys once the book exists.
  const ai = new AiCache(backend, CLOUD_PROVIDERS, (key) => drafts?.isSaved(key) ?? false);
  // Registered before the first await, so an event sent during boot is not missed.
  backend.on<string>("settings-place", (p) => {
    away = false;
    // An unknown page keeps the page on screen (placeOrCurrent); before the shell exists there is no page to keep.
    pending = shell ? placeOrCurrent(p, shell.current()) : migrate(p);
    const chatWasOpen = chatOpen;
    // A place already on screen is not built again: a rebuild would take what is typed and the banner with it.
    if (shell && !alreadyShown(pending, shell.current())) shell.select(pending);
    // A place that lands on a chat page already open (the window was hidden and is shown again, with no focus event) runs the arrival again: the cache throttles it.
    if (chatWasOpen && chatOpen) void aiArrive();
  });
  // The island changed a setting: the window holds it, cleaned as at boot, and the page on screen is drawn again. Pages write only through setValue and set, so a control in use keeps its value.
  backend.on<Partial<Settings>>("settings-changed", (s) => {
    if (!booted) { early = { ...early, ...s }; return; }
    settings = tidy({ ...settings, ...s });
    saver.echo(tidyEcho(s));
    shell?.sync();
  });
  // The window was hidden: what was typed and not saved is forgotten. A page that holds typed text is built again, so every field and chip is drawn from the (now empty)
  // draft book; the others have nothing to forget and are drawn as they are. While hidden, nothing is looked for: `away` holds the chat's refresh until the window is shown.
  // The first press or key after a hide clears `away`, so a window shown from the tray (with no focus event) still refreshes the AI page. One-shot listeners, re-armed at each hide.
  const onFirstAct = () => {
    if (!away) return;
    away = false;
    void aiArrive();
  };
  function armAway(): void {
    for (const t of ["pointerdown", "keydown"] as const) document.addEventListener(t, onFirstAct, { once: true });
  }
  backend.on<unknown>("settings-hidden", () => {
    drafts?.clearTyped();
    away = true;
    armAway();
    const place = shell?.current();
    if (shell && place && holdsTypedText(place)) shell.select(place);
    else shell?.sync();
    // The Devices Name goes back to the stored name: a hide while it is typed in keeps nothing.
    if (place?.page === "devices") devicesView?.reset();
  });
  // The servers' event is registered before the first await too: a list that arrives during boot is kept by the cache built above.
  backend.on<AiServer[]>("ai-servers-changed", (s) => {
    if (ai.setServers(s) && chatOpen) shell?.sync();
  });
  // The island's live projects (Settings → Cat → Project cats): the folder names, sent when they change and when this window asks once booted. Registered before the first await.
  let projectsLive: readonly LiveProject[] = [];
  backend.on<LiveProject[]>("projects-live", (list) => {
    projectsLive = namesOf(list);
    shell?.sync();
  });

  const boot = await backend.boot();
  const first = bootState(boot, IS_TAURI);
  settings = tidy({ ...first.settings, ...early });
  booted = true;
  // The island sends its live names now (main.ts answers with them, and again whenever they change).
  backend.askProjectsLive();
  // The boot's problem and its buttons, shown above the column until the person answers. Page changes do not clear them.
  let bootBanner: BootBanner | null = first.banner;
  let bootButtons = first.buttons;
  // A boot the command itself failed on, inside Tauri, is an unknown file: no save reaches the store until Try again (the in-memory defaults are not written over it).
  let refusing = boot === undefined && IS_TAURI;
  // Built before the first await below, so an echo that arrives while the keys are read finds it.
  const saver = makeSaver({
    write: (next) => (refusing ? Promise.resolve(false) : backend.save(next)),
    show: (s) => { settings = tidy(s); },
    // The control in use and its card, read now: the note goes in that card, or on the strip when no card holds it.
    focus: () => {
      const el = document.activeElement;
      if (!el) return null;
      return { el, card: el instanceof HTMLElement ? el.closest<HTMLElement>(".st-card") : null };
    },
    page: () => shell?.current().page ?? "",
    revert: (only) => forceValues(() => shell?.sync(), only),
    note: (place, card) => {
      if (place === "card" && card) {
        cardNote(card, "Couldn't save.");
        noteCard = card;
      } else shell?.banner({ text: "Couldn't save." });
    },
    clear: clearNote,
  }, settings);
  const present: Record<string, Presence> = {};
  // An unreadable store is its own answer: the field says so and nothing is written to that key until Check again finds the store readable.
  for (const k of KEYS) present[k] = await backend.secretPresence(k);
  drafts = new DraftBook(present, KEYS);
  for (const [id, text] of Object.entries(o.typed ?? {})) drafts.edit(id, text);

  const ctx: SettingsCtx = {
    backend,
    settings: () => settings,
    save: (next) => saver.save(next),
    home: boot?.home ?? "",
    drafts,
    open: (place) => shell?.select(place),
    platform: platformOf(navigator.platform),
    desktopNote: boot && !boot.desktopPositioned ? GNOME_NOTE : null,
    ai,
    projects: () => projectsLive,
  };

  /** Takes the "Couldn't save." note away, wherever it is. */
  function clearNote(): void {
    clearCardNote(noteCard);
    noteCard = null;
    shell?.banner(null);
  }

  /** The boot's banner, pinned above the page strip: its words, its tone and its buttons. Painted again after each answer. */
  function paintBootBanner(): void {
    shell?.pin(bootBanner
      ? {
        text: bannerText(bootBanner),
        kind: bootBanner.kind === "unparseable" ? "warn" : "err",
        actions: bootButtons.map((label) => ({ label, onClick: () => answerBoot(label) })),
      }
      : null);
  }

  /** The banner is answered: nothing of the problem stands any more. */
  function clearBoot(): void {
    bootBanner = null;
    bootButtons = [];
    paintBootBanner();
  }

  /** The banner's buttons: Try again reads the file once more, Start fresh accepts the defaults, Dismiss takes the banner away. */
  function answerBoot(label: string): void {
    if (label === "Try again") void tryAgain();
    else if (label === "Start fresh") void startFresh();
    else clearBoot();
  }

  /** Try again: the file is read once more, without a backup. A read that works replaces the settings, clears the banner and the refusal, and syncs the pages; one that
   * fails says so on the page strip. */
  async function tryAgain(): Promise<void> {
    const r = await backend.settingsRetryLoad();
    if (!r.ok || !r.value) { shell?.banner({ text: r.ok ? "Your settings file still couldn't be read." : r.error }); return; }
    settings = tidy({ ...DEFAULT_SETTINGS, ...r.value });
    saver.echo(settings);
    refusing = false;
    clearBoot();
    forceValues(() => shell?.sync(), null);
  }

  /** Start fresh: the person accepts the defaults and the store's refusal is cleared. The store refuses it while the file reads; nothing is written here. */
  async function startFresh(): Promise<void> {
    const r = await backend.settingsStartFresh();
    if (!r.ok) { shell?.banner({ text: r.error }); return; }
    refusing = false;
    clearBoot();
  }

  // The chat's arrival: the cache looks at Claude Code, the servers and the saved providers' lists (it throttles itself), and the page is drawn again when that changed it.
  async function aiArrive(): Promise<void> {
    if (!chatOpen || away) return;
    if ((await ai.refreshOnOpen()) && chatOpen) shell?.sync();
  }

  document.body.classList.add("st-app");
  shell = buildShell({
    version: boot?.version ?? "",
    build: (place) => {
      // The arrival runs once, when the chat page opens (not on each of its tabs); focus and visibility bring it back while the chat is open.
      const arrived = place.page === "chat" && !chatOpen;
      chatOpen = place.page === "chat";
      if (arrived) void aiArrive();
      return buildPage(place, ctx, (d) => { devicesView = d; });
    },
    storage: o.storage,
    initial: pending ?? o.initial ?? null,
  });
  root.replaceChildren(shell.el);
  paintBootBanner();
  window.addEventListener("focus", () => { away = false; shell?.fit(); void aiArrive(); });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") return;
    away = false;
    shell?.fit();
    void aiArrive();
  });
}

/** The page for a place. Every page is built; a chat tab that is not one of the named ones is drawn as the Your AI tab. */
function buildPage(place: Place, ctx: SettingsCtx, onDevices: (d: { reset(): void }) => void): PageView {
  switch (place.page) {
    case "general": return generalPage(ctx);
    case "agents": return agentsPage(ctx);
    case "chat":
      switch (place.tab) {
        case "keys": return keysTab(ctx, CLOUD_PROVIDERS);
        case "localmodels": return localModelsTab(ctx);
        case "sidekick": return sidekickSection({
          sidekick: () => ctx.settings().sidekick,
          put: (next) => void ctx.save({ ...ctx.settings(), sidekick: next }),
          found: async () => (await ctx.backend.aiLocalModel()) ?? null,
        });
        case "companion": return companionTab({
          settings: () => ctx.settings().companion,
          put: (next) => void ctx.save({ ...ctx.settings(), companion: next }),
          lastSent: () => ctx.backend.companionLastSent(),
          conversations: () => ctx.backend.companionCount(),
          deleteAll: () => ctx.backend.companionDeleteAll(),
          brain: async () => {
            const r = await ctx.backend.aiResolve("chat");
            const authMethod = r?.provider === "claudeCode" ? ((await ctx.backend.claudeStatus())?.authMethod ?? null) : null;
            return brainNameOf(r, authMethod);
          },
        });
        default: return yourAiTab(ctx, CLOUD_PROVIDERS);
      }
    case "services": return servicesPage(ctx);
    case "cat": {
      // The shell disposes the page when another tab is shown, which stops its loop. A slider's drag is held until the slider lets go: the page works from `reconcile`, so an
      // island change that arrives during the drag is shown, and the release saves the drag's fields over the latest block.
      let held: Held | null = null;
      return catSection({
        cat: () => reconcile(held, ctx.settings().cat),
        put: (next, final) => {
          const latest = ctx.settings().cat;
          if (!final) { held = hold(held, latest, next); return; }
          const block = released(held, latest, next);
          held = null;
          void ctx.save({ ...ctx.settings(), cat: block });
        },
        desktopNote: ctx.desktopNote,
        projects: ctx.projects,
      }, (place.tab ?? "look") as CatTab);
    }
    case "devices": {
      // The section syncs itself from the link's own snapshots, so the shell's sync() does not call it.
      const d = devicesSection({ backend: ctx.backend.link, platform: ctx.platform });
      onDevices(d);
      return { el: d.el, dispose: () => d.dispose() };
    }
  }
}
