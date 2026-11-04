// Entry point: boot the bridge, wire the island, start the greeting.

import "./style.css";
import { Bridge, IS_TAURI, onEvent } from "./core/bridge";
import { Sound } from "./core/sound";
import { State, type Settings } from "./core/state";
import { withDisplayMode } from "./cat/display";
import { Island } from "./island/island";
import type { ButtonEvent } from "./island/outsideclick.ts";
import { DesktopBrain } from "./island/desktop";
import { handleHook, registerHookHandlers, takeHook, setDevForeground, type HookPayload } from "./island/hooks";
import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
import { Skew, sidekickEnv } from "./sidekick/appenv";
import { Sidekick } from "./sidekick/controller.ts";
import { Hub } from "./sidekick/hub.ts";
import { bridgeBackend, mockBackend } from "./shelf/backend";
import { bridgeLinkBackend } from "./link/backend";
import { ShelfLook, linkChanged } from "./island/link";
import "./link/link.css";
import "./projects/projects.css";
import "./companion/companion.css";
import { ProjectsModel } from "./projects/model.ts";
import { islandLink } from "./companion/link.ts";
import { applyToIsland } from "./companion/windowlink.ts";
import { bridgeStore } from "./companion/store.ts";
import { bridgeChat, forgetDeletedAll, noteInChat, openConversation, startNewChat } from "./companion/session.ts";
import { OPEN_FAILED_NOTE } from "./companion/chrome.ts";

async function main() {
  const root = document.getElementById("root");
  if (!root) return;

  // `/?dev` is the cat contact sheet. The dev server only: a release build does not contain it.
  if (import.meta.env.DEV && new URLSearchParams(location.search).has("dev")) {
    const { mountDev } = await import("./cat/dev");
    mountDev(root);
    return;
  }

  void Sound.preload();

  // Before the island exists: its canvases size their bitmaps from the pixel ratio once, so a zoom correction has to land first (see `fit_zoom` in lib.rs).
  // If the zoom changed, wait until the ratio follows it, for 500 ms at most.
  const dprBefore = window.devicePixelRatio || 1;
  if (await Bridge.fitZoom(dprBefore)) {
    for (let i = 0; i < 20 && window.devicePixelRatio === dprBefore; i++) await new Promise((r) => setTimeout(r, 25));
  }

  const island = new Island(root);

  const boot = await Bridge.boot();
  if (boot) {
    State.settings = { ...State.settings, ...boot.settings };
  }
  // Dev server only: `/?display=two` starts in that display mode, for looking at it without the Settings window.
  if (import.meta.env.DEV) {
    const mode = new URLSearchParams(location.search).get("display");
    if (mode) State.settings.cat = withDisplayMode(State.settings.cat, mode);
  }
  island.applySettings();
  // A coat given to an agent is saved, so it keeps it. The save is set before the load, so a switched-on agent's coat given at load is saved too.
  State.persistSettings = () => void Bridge.saveSettings(State.settings);
  State.loadIntegrationTasks();
  // The pills that exist now get their coats once, before anything is drawn.
  State.giveCoats();
  // The desktop cat (sub-project H): this page runs its trip, and the desktop window's page draws it.
  const desktop = new DesktopBrain(island.desktopHost());
  island.attachDesktop(desktop);
  island.setCursorPoll(boot ? boot.cursorPoll : true);
  if (boot?.shelf) State.shelfCaps = { dragOut: boot.shelf.dragOut, send: boot.shelf.send };
  if (boot) State.claudeApp = boot.claudeApp;
  if (boot) State.foregroundKind = boot.foreground;
  if (boot && !boot.cursorPoll) island.followPageCursor();
  // The shelf (sub-project G1): Rust's store inside the app, a small one in memory in a plain browser. Read once at launch, so the badge knows the count.
  State.shelf.attach(IS_TAURI ? bridgeBackend() : mockBackend());
  void State.shelf.refresh();
  // The link between this machine and the user's others (sub-project G2): Rust's service inside the app, a stand-in on the dev server, nothing in a release build opened in a browser.
  // The snapshot decides what the island does for a card (island/link.ts); the shelf says when it is on screen, so that Rust looks for the machines only then.
  const linkBackend = IS_TAURI ? bridgeLinkBackend() : import.meta.env.DEV ? (await import("./link/mock")).mockLinkBackend() : null;
  if (linkBackend) State.link.attach(linkBackend, (prev, next) => linkChanged(island, prev, next));
  const shelfLook = new ShelfLook();
  State.subscribe(() => shelfLook.sync(State.view, State.mode, (open) => State.link.backend?.setShelfOpen(open)));
  // Dev server only: a small tab in the compact island that drags a test file out, to try the native drag source on a real machine (shelf/dragspike.ts).
  if (import.meta.env.DEV) void import("./shelf/dragspike").then((m) => m.mountDragSpike());

  await onEvent<{ x: number; y: number; down?: boolean }>("cursor", ({ x, y, down }) => island.onCursor(x, y, down));
  // The outside click (island/outsideclick.ts): a mouse button went down or came up while the island is expanded.
  await onEvent<ButtonEvent>("pointer-button", (e) => island.onPointerButton(e));

  /** Pause has to reach Rust too, or the pollers keep calling out. */
  const setPaused = (on: boolean) => {
    if (State.paused === on) return;
    State.paused = on;
    void Bridge.setPaused(on);
  };

  await onEvent<string>("tray", (what) => {
    switch (what) {
      case "settings":
        setPaused(false);
        island.alert("settings");
        break;
      case "open":
        setPaused(false);
        island.alert(State.defaultView());
        break;
      case "desktop":
        void desktop.toggle();
        break;
      case "shelf":
        setPaused(false);
        island.openShelf();
        break;
      case "projects":
        setPaused(false);
        island.openProjects();
        break;
      case "pause":
        setPaused(!State.paused);
        if (State.paused) island.fsm.forceHidden();
        else island.reveal();
        break;
    }
  });

  const checkZoom = () => Bridge.fitZoom(window.devicePixelRatio || 1);
  await onEvent<null>("screen-changed", async () => {
    await checkZoom();
    void Bridge.reposition();
    desktop.screenChanged();
  });
  // A change of the pixel ratio (the window moved to another display, text scaling changed) is a media query that stops matching.
  window.matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`).addEventListener?.("change", () => void checkZoom());
  // Ctrl+wheel and Ctrl+plus/minus would zoom the island's page by themselves and undo the correction.
  window.addEventListener("wheel", (e) => { if (e.ctrlKey) e.preventDefault(); }, { passive: false });
  window.addEventListener("keydown", (e) => { if (e.ctrlKey && (e.key === "+" || e.key === "-" || e.key === "=" || e.key === "0")) e.preventDefault(); });

  // The platform's own news of a lock, an unlock, a sleep, a wake and the display (Rust: `sidekick::away_changed`): the Sidekick decides what they mean.
  await onEvent<{ signal: string }>("sidekick-away", ({ signal }) => Hub.sk?.presenceSignal(signal));

  // The settings window writes preferences; apply them here without a restart.
  await onEvent<Settings>("settings-changed", (s) => {
    State.settings = { ...State.settings, ...s };
    island.applySettings();
    island.settingsChanged();
    State.loadIntegrationTasks();
    void refreshConfigured();
    desktop.settingsChanged();
    Hub.sk?.settingsChanged();
  });

  // The Projects registry (sub-project P): memory only, one model for the session, with the home folder and the same clock the Sidekick reads.
  State.projects = new ProjectsModel({ home: boot?.home ?? "", now: () => Date.now() + Skew.ms });
  // Settings → Cat → Project cats: the Settings window asks for the live folder names once it boots; they are sent again whenever they change (below). Names only, never a path.
  await onEvent<null>("projects-live-ask", () => void Bridge.emitProjectsLive(State.projects.liveProjects(State.projectsNow().view)));
  // The Sidekick (sub-project F1): it is told every hook event before the island's own handler can refuse it.
  Hub.sk = new Sidekick(sidekickEnv(island, boot?.home ?? ""));
  State.subscribe(() => Hub.sk?.stateChanged());
  // The tray's Projects item says how many projects there are; the words are sent only when the count changes (tray.rs projects_text).
  let lastProjects = -1;
  // The live folder names go to the Settings window only when they change: the same text is never sent twice.
  let lastLive = "";
  State.subscribe(() => {
    const n = State.projectsNow().view.projects.length;
    if (n !== lastProjects) {
      lastProjects = n;
      void Bridge.projectsMenuText(n);
    }
    const live = State.projects.liveProjects(State.projectsNow().view);
    const text = JSON.stringify(live);
    if (text !== lastLive) {
      lastLive = text;
      void Bridge.emitProjectsLive(live);
    }
  });
  registerHookHandlers(island);
  // The chat's pop-out window (companion/windowlink.ts). While it is shown the island pushes it the chat's context on each State.notify, and only when it changed (as JSON);
  // nothing is pushed while the chat is in the island. Messages from the window are checked before they are acted on, and only count while the chat is popped out.
  let lastChatContext = "";
  State.subscribe(() => {
    if (!State.chatPoppedOut) {
      lastChatContext = "";
      return;
    }
    const msg = { kind: "context", context: State.contextNow(), approval: State.chatApprovals.front };
    const text = JSON.stringify(msg);
    if (text === lastChatContext) return;
    lastChatContext = text;
    void Bridge.chatRelay("chat", msg);
  });
  await onEvent<unknown>("chat-msg", (raw) => applyToIsland(raw, islandLink()));
  await onEvent<unknown>("companion-deleted-all", () => forgetDeletedAll(islandLink(), bridgeChat));
  // The window was closed (or Bring it back): the island takes the chat back, on the conversation the window last saved. A hide the island asked for itself (a drop) finds the chat already back.
  await onEvent<null>("chat-window-hidden", () => {
    if (!State.chatPoppedOut) return;
    State.chatPoppedOut = false;
    State.notify();
    // The window may have moved the conversation on: it is read again from its file. With no saved conversation the chat starts new (Rust holds the window's turns).
    // One that cannot be opened also starts new, but the chat says so: it never starts quietly.
    void (async () => {
      if (State.chatId === null) startNewChat(islandLink(), bridgeChat);
      else if (!(await openConversation(bridgeStore, State.chatId, islandLink(), bridgeChat))) {
        startNewChat(islandLink(), bridgeChat);
        noteInChat(OPEN_FAILED_NOTE);
      }
      State.notify();
    })();
  });
  // Dev server only: `window.__nm.hook({...})` feeds the island the same hook JSON the relay would, so the pair and the kittens can be looked at without a real agent.
  if (import.meta.env.DEV) (window as unknown as { __nm: unknown }).__nm = { island, State, hook: (payload: HookPayload) => handleHook(island, payload) };
  if (import.meta.env.DEV) (window as unknown as { __nm: { sk: unknown } }).__nm.sk = Hub.sk;
  if (import.meta.env.DEV) Object.assign((window as unknown as { __nm: Record<string, unknown> }).__nm, { take: (payload: HookPayload) => takeHook(island, payload), foreground: setDevForeground });
  if (import.meta.env.DEV) (window as unknown as { __nm: { link: unknown } }).__nm.link = State.link.backend;
  // Dev server only: scripted runs of the Sidekick (`__nm.run.recap()`, `loop()`, `waiting()`, `quiet()`, `card("high")`...) and its clock (`__nm.skew(ms)`), for the pictures and the owner's look.
  // The Projects scenarios (`__nm.projects.run("many")`, `__nm.projects.age(5)`) go through the same hook path and the same clock: only the Sidekick's dev scenarios move the clock.
  if (import.meta.env.DEV) {
    void import("./sidekick/dev").then(async ({ sidekickScenarios }) => {
      const run = sidekickScenarios(island, Hub.sk!, (p: HookPayload) => handleHook(island, p));
      Object.assign((window as unknown as { __nm: Record<string, unknown> }).__nm, { run, skew: run.skew });
      const { projectScenarios } = await import("./projects/dev");
      const projects = projectScenarios((p) => handleHook(island, p as HookPayload), (ms) => { run.skew(ms); State.notify(); });
      Object.assign((window as unknown as { __nm: Record<string, unknown> }).__nm, { projects });
    });
  }
  registerIntegrationHandlers(island);
  await desktop.start();

  island.launch();

  // In a plain browser there is no wake strip behind the cursor: make the whole
  // page wake the island so the visuals can be checked with `npm run dev`.
  if (!IS_TAURI) {
    document.addEventListener("click", () => Sound.resume(), { once: true });
  }
}

void main();
