// The island: DOM shell, sizing animation, cat placement, mouse handling.
// Mirrors IslandRootView.swift + IslandWindowController.swift.

import { Tracked, Spring, clamp } from "../core/anim";
import { Bridge, IS_TAURI, onDragDrop, type DroppedFile } from "../core/bridge";
import {
  EXPANDED_CORNER, EXPANDED_W, NOTCH_H, NOTCH_W, PANEL_H, PANEL_W,
  ROUNDED_CORNER, VIEW_LAYOUTS, botGlowColor, botGlowOpacity, botPosition, chatPromptHeight, pairPlacement,
  bigCatPressed, catClickTarget, islandSize,
  type BotEmoteName, type BotStateName, type Circle, type IslandMode, type IslandViewName,
} from "../core/layout";
import { forgetDrop } from "../core/feature";
import { DESKTOP_CATCH_WAIT_MS } from "../cat/desktop";
import { Sound } from "../core/sound";
import { State } from "../core/state";
import type { Cast } from "../cat/cast";
import { bigCatCollar } from "../cat/collar";
import { shouldDance } from "../cat/dance";
import { BotEngine, CATCH, catCfg } from "../cat/engine";
import { cleanCatBlock, withOutfit } from "../cat/display";
import { applyCatSettings } from "../cat/settings";
import { seg } from "../cat/base";
import { FLIGHT_MS, cursorLook } from "../cat/geometry";
import { Greeting, greetingShown } from "../cat/greeting";
import { KittenPool, drawKittens } from "../cat/kittendraw";
import { kittenPlaceOf } from "../cat/kittens";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickKittenStrips, tickMiniBots } from "../cat/minibots";
import { PressDrag } from "../cat/pressdrag";
import { wardrobeMenuHit } from "../cat/menuhit";
import type { OutfitId } from "../cat/wardrobe";
import { Menu, Submenu } from "@tauri-apps/api/menu";
import { buildPinMenu, type PinMenu } from "../core/pinmenu.ts";
import { PANEL_EXTRA, PIN_MENU_RELEASE_MS } from "../projects/cells.ts";
import { CLAUDE_COLOR, badgeTitle, pinTitle, projectKittens } from "../projects/present.ts";
import type { ProjectsFrame } from "../projects/model.ts";
import { ProjectsTick } from "../projects/clock.ts";
import { leaveAllPeeks } from "../views/projects.ts";
import { buildWardrobeItems, tickWardrobe } from "../core/wardrobemenu";
import type { WardrobeItems } from "../core/wardrobemenu";
import { notchCatLocal } from "../core/notchspot";
import { finishedAction, openRoute } from "../core/openagent.ts";
import { UploadCanvas } from "../upload/canvas";
import { badgeLabel, badgePlace, badgeShown, badgeTitle as shelfBadgeTitle } from "../shelf/badge";
import { DragOutGuard } from "../shelf/dragguard";
import { dropZone, planDrop } from "../shelf/dropflow";
import { ShelfZones } from "../shelf/zones";
import type { Zone } from "../shelf/rules";
import { classifyIngestError, noteSound } from "../upload/refusal";
import { USC, UploadSeq } from "../upload/sequence";
import { buildHeader, buildViews, type ViewActions, type ViewHost } from "../views/views";
import { h } from "../views/dom";
import { IslandStateMachine } from "./fsm";
import { isLive } from "./tuckaway.ts";
import { SendHold } from "./sendhold.ts";
import { OutsideClick, type ButtonEvent, type OutsideContext } from "./outsideclick.ts";
import { SPRING_DAMPING, SPRING_RESPONSE, foldedHitRect, isActive as wingIsActive, stepFade, widthAt, wings, zoneOf, type WingOut, type Zone as WingZone } from "./wing.ts";
import { WingDriver } from "./wingdriver.ts";
import { SleepClock } from "./sleep";
import { WardrobeClock } from "./wardrobe";
import { releaseChatApprovals, resurfaceChatApproval } from "./hooks";
import { Hub } from "../sidekick/hub.ts";
import { NOT_COPIED_LINE, agentCatAt, copiedLine, dropAgents, dropPoint, pathsText } from "../sidekick/agentdrop.ts";
import { platformName } from "../sidekick/platform.ts";
import { emoteMiniBots } from "../cat/minibots";
import { AgentDropStrip } from "../views/agentdrop";
import type { DesktopBrain, DesktopHost } from "./desktop";

const BOT_OVERHANG = 40;
/** The kittens' overlay: from the island's left edge, as wide as the expanded island and as high as its overview plus the kittens under the cat. */
const KITTEN_W = EXPANDED_W;
const KITTEN_H = 170;
/** Seconds from the cat's refusal to the note: the pause before it starts heaving, and the hairball (the engine's `CATCH`). */
const HAIRBALL_S = (CATCH.gag + CATCH.hairball) / 1000;
/** How long the island stays open after the Share window was asked for (ms): the window is the system's, and nothing tells us when it closes. */
const SEND_HOLD_MS = 15_000;
/** Same margin as the Rust hit test (src-tauri/src/island.rs). */
const HIT_MARGIN = 14;

/** The width of the page in CSS px; the island is centred in it. It is PANEL_W unless the webview's zoom made the viewport narrower or wider than the window. */
function viewportWidth(): number {
  return window.innerWidth > 0 ? window.innerWidth : PANEL_W;
}

/** The three views the drop sequence owns; leaving them stops the engine. */
const UPLOAD_VIEWS: ReadonlySet<IslandViewName> = new Set(["upload", "uploading", "choose"]);

/** Seconds between the drop and the moment the progress bar starts filling. */
const PRE_PROGRESS = USC.T_PROG_START - USC.T_DROP;

const modeOrder = (m: IslandMode) => (m === "hidden" ? 0 : m === "compact" ? 1 : 2);

export class Island {
  readonly fsm = new IslandStateMachine();

  /** The cats' ten-minute nap: one timer, started by every event, never a poll (island/sleep.ts). */
  private sleep = new SleepClock({
    now: () => performance.now(),
    state: () => State.stateOverride ?? State.focusTask?.state ?? "idle",
    blocked: () => State.attentionNeeded || State.linkOfferPending,
    set: (fn, ms) => window.setTimeout(fn, ms),
    clear: (id) => window.clearTimeout(id),
    fall: () => State.fallAsleep(),
    sweep: () => State.sweepKittens(),
    wake: () => State.wake(),
  });

  /** Auto's one-shot (sub-project I): the outfit is the stored choice resolved for today, looked at again at the next local midnight, and only while the choice is `auto` (island/wardrobe.ts). */
  private wardrobe = new WardrobeClock({
    now: () => new Date(),
    choice: () => State.settings.cat.outfit,
    set: (fn, ms) => window.setTimeout(fn, ms),
    clear: (id) => window.clearTimeout(id),
    apply: (outfit) => { State.outfit = outfit; State.notify(); },
  });

  private root: HTMLElement;
  private islandEl!: HTMLElement;
  private clipEl!: HTMLElement;
  private haloEl!: HTMLElement;
  private contentEl!: HTMLElement;
  private viewsEl!: HTMLElement;
  private botCanvas!: HTMLCanvasElement;
  /** Two cats mode: the second cat's canvas, beside the first. */
  private botCanvas2!: HTMLCanvasElement;
  /** Subagent kittens beside the big cat and the pair: one overlay canvas over the island (kittendraw.ts). */
  private kittenCanvas!: HTMLCanvasElement;
  private kittenPool = new KittenPool();
  private kittensDrawn = false;
  private botGlow!: HTMLElement;
  private greetingCanvas!: HTMLCanvasElement;
  private miniGrid!: HTMLElement;
  /** The compact notch's amber dots on the big cat and on cat 2 (focus awareness; placed in placeFocusDots). */
  private focusDotBig!: HTMLElement;
  private focusDotSecond!: HTMLElement;
  /** The shelf's count at the right end of the compact island's wing (sub-project G1). */
  private shelfBadge!: HTMLElement;
  /** The waiting count at the same place (sub-project P): shown while a session waits, the shelf's badge after it. */
  private waitBadge!: HTMLElement;
  /** Whether the Claude-only card's section was open at the last sync: a change moves the island on the spring (targetSize). */
  private panelWasShown = false;
  /** The Projects frame of this animation frame (sub-project P): computed once at the top of `frame` and again by `syncDom`, read by the big cat, its peek and its kittens. */
  private projectsFrame: ProjectsFrame | null = null;
  /** The one tick of the Projects frame (projects/clock.ts): the next time a state changes, while the island is open. */
  private projectsTick = new ProjectsTick({ set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) }, () => Date.now(), () => State.projects.nextDelay(), () => State.notify());
  private countdown!: HTMLElement;
  private wakeStrip!: HTMLElement;

  /** The agents' cats shown while a file is dragged over the island (sub-project F1): a drop on one copies the file's path. */
  private agentDrops = new AgentDropStrip();
  private header!: ViewHost;
  private views!: Map<IslandViewName, ViewHost>;
  private uploadCanvas!: UploadCanvas;
  /** The Ask and Shelf halves of the drop view: a layer over the drop canvas, never a change to it (sub-project G1). */
  private zones!: ShelfZones;
  /** The OS has a global cursor, so `State.mouseInIsland` is the pointer during a drag (Windows). Where it has none (Wayland) the drag event's own position is. */
  private cursorPoll = true;
  /** The last position a drag event carried (physical px of the webview). */
  private dragPos: { x: number; y: number } | null = null;
  /** A shelf item is being dragged out of the island, or just was: a drop that comes back to the island is its own (shelf/dragguard.ts). */
  private dragOut = new DragOutGuard();
  /** The shelf's send holds the island for its Share window and 15 s after; each send replaces the last one's timer (island/sendhold.ts). */
  private sendHold = new SendHold((on) => this.fsm.setShelfHold("send", on), SEND_HOLD_MS);
  /** A click outside the open island folds it (island/outsideclick.ts). Fed the button edges Rust sends while `watchingButtons`; the fold is the same as Escape's. */
  private outside = new OutsideClick((e) => this.outsideContext(e), () => this.collapse());
  /** The compact island's wings step aside (island/wing.ts): the rules' memory plus its one one-shot wake-up. The swoosh is 0 at rest and 1 folded into the notch-wide middle, moved by a spring. */
  private swoosh = new Tracked(0);
  private wingFade = 1;
  private wing = new WingDriver(
    { now: () => performance.now() / 1000, set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
    () => this.mouseButtonDown,
    (now) => this.onWingChange(now),
  );
  /** A mouse button is held, as far as the page can tell: its own mouse events while the window takes the mouse, the cursor event's `down` otherwise. */
  private mouseButtonDown = false;
  /** `onCursor` is running: a change of the wing's answer inside it is handled by the code that follows. */
  private inCursor = false;
  /** Rust has been asked to read the mouse buttons (the island is expanded and the OS has a global pointer). */
  private watchingButtons = false;
  /** A file was dropped and the catch is waiting for the desktop cat to reach the notch (`whenCatIsHere`); the file is still "on its way in" to the desktop cat meanwhile. */
  private dropWaiting = false;

  private width = new Tracked(NOTCH_W);
  private height = new Tracked(0);
  private radius = new Tracked(ROUNDED_CORNER);
  private botCx = new Spring(46);
  private botCy = new Spring(16);
  private botSize = new Spring(10);
  private bot2Cx = new Spring(46);
  private bot2Cy = new Spring(16);
  private bot2Size = new Spring(10);

  private engine = new BotEngine();
  /** Two cats mode: the second cat, in the pair's second coat, showing the busiest other agent. */
  private engine2 = new BotEngine();
  /** The cast of the frame (State.cast): which coat each cat wears. */
  private cast: Cast = State.cast;
  /** The second cat is on screen this frame (Two cats mode, compact or the overview, no greeting or drop on top). */
  private pairShown = false;
  private greeting = new Greeting();
  /** The desktop cat's brain (island/desktop.ts), attached by main.ts once the screens are known. */
  private desktop: DesktopBrain | null = null;
  /** A press on the big cat of the notch: a click when the button comes up, or the start of a drag out of the notch (sub-project H). */
  private press = new PressDrag();
  private pressAction: (() => void) | null = null;

  private running = false;
  private lastFrame = 0;
  private dirty = true;
  private canvasPx = 0;
  private canvas2Px = 0;

  // Rust starts the window at full size so the launch greeting has room.
  private collapsed = false;
  private collapseTimer: number | null = null;
  private wasInIsland = false;
  /** Last shape handed to Rust for the click-through test. */
  private pushedRect = { x: -1, y: -1, w: -1, h: -1 };
  private homeCollapseAt: number | null = null;

  // Bot hover → love (IslandWindowController.botHoverIn)
  private botHovering = false;
  private botHoverTimer: number | null = null;
  private lastLoveTime = 0;
  private botHoverStart = { x: 0, y: 0 };

  private confusedRecovery: number | null = null;
  private prevViewBeforeConfused: IslandViewName = "overview";
  private lastSyncedView: IslandViewName | null = null;

  /** Drop sequence bookkeeping: last tick played, and whether the ✓ has fired. */
  private uploadTens = 0;
  private uploadDone = false;
  /** Counts the drops, so the note a refusal delays can tell that another drop has happened since. */
  private dropCount = 0;
  /** The token of the latest Shelf drop: an Ask copy at or below it landed behind a Shelf drop, so it plays nothing and attaches nothing. */
  private shelfDropToken = -1;
  /** The latest file catch: a drop waiting for the desktop cat runs only while no newer drop has started (`whenCatIsHere`). Moves at the drop, unlike `dropCount`. */
  private catchTurn = 0;

  constructor(root: HTMLElement) {
    this.root = root;
    this.build();
    this.wireFsm();
    this.wireInput();
    this.engine.onDizzy = () => this.handleDizzy();
    this.greeting.onComplete = () => { this.fsm.greetComplete(); this.desktop?.afterGreeting(); };
    // The last beat is over: sync the DOM, so the real cat and the real grid fade in as the greeting canvas fades out.
    this.greeting.onEnd = () => State.notify();
    State.subscribe(() => {
      this.dirty = true;
      this.ensureRunning();
    });
  }

  // ── DOM ─────────────────────────────────────────────────────────────────────

  private build() {
    const actions: ViewActions = {
      setView: (v) => this.setView(v),
      collapse: () => this.collapse(),
      setFocus: (id) => {
        State.setFocus(id);
        Sound.play("blip");
      },
      openTerminal: () => this.openAgent(State.focusTask?.id, State.focusTask?.sessionCwd ?? null),
      // The ↗ button — same targets as openAgentTarget() on macOS.
      openTarget: () => {
        const task = State.focusTask;
        if (!task) return;
        const urls: Record<string, string> = {
          integration_resend: "https://resend.com/emails",
          integration_vercel: "https://vercel.com/dashboard",
          integration_github: "https://github.com",
          integration_stripe: "https://dashboard.stripe.com/payments",
          integration_notion: "https://notion.so",
          integration_calcom: "https://app.cal.com/bookings",
        };
        if (openRoute(task.id, State.claudeApp, State.claudeAppHost) === "claude-app") void Bridge.openClaudeApp();
        else if (task.id === "integration_claude") void Bridge.openInVSCode(task.sessionCwd ?? null);
        else if (task.id === "integration_n8n") void Bridge.openN8n();
        else if (urls[task.id]) void Bridge.openUrl(urls[task.id]);
      },
      openUrl: (url) => {
        if (url) void Bridge.openUrl(url);
      },
      decide: (d) => {
        const req = State.pendingApproval;
        void Bridge.log(`decide ${d} req=${req?.requestId ?? "none"}`);
        if (!req) return;
        Sound.play(d === "deny" ? "blip" : "approve");
        void Bridge.approvalDecision(req.requestId, d);
        Hub.sk?.approvalAnswered(req.pillId, req.sessionId);
        State.subagentApprovalOver(req);
        State.pendingApproval = null;
        State.isPinned = false;
        this.fsm.pinned = false;
        State.updateTask("integration_claude", "working");
        State.setPillBadge("integration_claude", null);
        this.setView(State.defaultView());
        // A chat card still queued comes back after the user's own approval.
        resurfaceChatApproval(this);
      },
      toggleSound: () => {
        State.settings.soundEnabled = !State.settings.soundEnabled;
        Sound.setEnabled(State.settings.soundEnabled);
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      setVolume: (v) => {
        State.settings.soundVolume = v;
        Sound.setVolume(v);
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      setAutoClose: (s) => {
        State.settings.autoCloseInterval = s;
        this.fsm.homeToPetitDelay = s;
        void Bridge.saveSettings(State.settings);
        State.notify();
      },
      sidekickDismiss: () => {
        Hub.sk?.noteDismissed();
        this.collapse();
        Hub.sk?.noteCollapsed();
      },
      sidekickOpen: () => {
        const id = State.sidekickNote?.agentId;
        this.openAgent(id, State.tasks.find((t) => t.id === id)?.sessionCwd ?? null);
      },
      openSettingsWindow: (place?: string) => void Bridge.openSettingsWindow(place),
      blip: () => Sound.play("blip"),
      emote: (name) => this.engine.triggerEmote(name),
      shelf: { ask: (id) => this.askShelf(id), send: (ids) => this.sendShelf(ids), reveal: (id) => this.revealShelf(id), dragOut: (ids) => this.dragOutShelf(ids) },
      projects: {
        select: (id) => {
          State.projects.select(id);
          Sound.play("blip");
          State.notify();
        },
        jumpProject: (id) => {
          const p = State.projectsNow().view.projects.find((x) => x.id === id);
          const s = p ? State.projects.newestSession(p) : null;
          if (s) this.jumpToSession(s.id);
        },
        jumpSession: (id) => this.jumpToSession(id),
        menu: (id) => void this.showProjectMenu(id),
        toggleExpanded: () => {
          State.projects.toggleExpanded();
          State.notify();
        },
        openScreen: () => this.openProjects(),
      },
    };

    this.wakeStrip = h("div", { id: "wake-strip" });
    this.botGlow = h("div", { id: "bot-glow" });
    this.botCanvas = h("canvas", { id: "bot-canvas" });
    this.botCanvas2 = h("canvas", { id: "bot2-canvas" });
    this.kittenCanvas = h("canvas", { id: "kitten-canvas" });
    this.greetingCanvas = h("canvas", { id: "greeting-canvas" });
    this.miniGrid = h("div", { id: "mini-grid" });
    this.focusDotBig = h("span", { class: "fa-compact-dot" });
    this.focusDotSecond = h("span", { class: "fa-compact-dot" });
    // A press on the badge opens the shelf and is nothing else: it must not reach the island's own press, which opens the island on its Home view.
    this.shelfBadge = h("button", { id: "shelf-badge" });
    this.shelfBadge.addEventListener("mousedown", (e) => e.stopPropagation());
    this.shelfBadge.addEventListener("click", (e) => { e.stopPropagation(); this.openShelf(); });
    // The waiting count (sub-project P): a press on it opens the Projects screen and is nothing else, as the shelf's does.
    this.waitBadge = h("button", { id: "projects-badge" });
    this.waitBadge.addEventListener("mousedown", (e) => e.stopPropagation());
    this.waitBadge.addEventListener("click", (e) => { e.stopPropagation(); this.openProjects(); });
    this.countdown = h("div", { id: "countdown" });

    this.header = buildHeader(actions);
    this.views = buildViews(actions, () => this.animateGeometry(false));
    this.viewsEl = h("div", { id: "views" });
    for (const v of this.views.values()) this.viewsEl.append(v.el);
    this.contentEl = h("div", { id: "content" }, this.header.el, this.viewsEl);

    // The drop sequence draws the card, the bar and its own cat. It sits under
    // the header, which stays visible on top of it exactly as on macOS.
    this.uploadCanvas = new UploadCanvas({
      ask: () => {
        State.promptContext = State.droppedFile
          ? { kind: "file", name: State.droppedFile.name, path: State.droppedFile.path }
          : null;
        this.setView("prompt");
      },
      cancel: () => this.setView(State.defaultView()),
    });
    // A file on its way in is an alert to the desktop cat (cat/desktop.ts `desktopAlert`): the drag over the island, a drop waiting for the cat, or the drop flow on screen.
    State.fileCatch = () => State.fileDragOver || this.dropWaiting || this.uploadActive;

    this.zones = new ShelfZones();
    this.clipEl = h(
      "div",
      { id: "island-clip" },
      this.greetingCanvas,
      this.uploadCanvas.el,
      this.zones.el,
      this.contentEl,
    );
    // The hover glow's halo: its own element, first in the island, so the blur spills past the ring's mask (style.css "The hover glow").
    this.haloEl = h("div", { id: "island-halo" });
    this.islandEl = h(
      "div",
      { id: "island" },
      this.haloEl,
      this.clipEl,
      this.botGlow,
      this.botCanvas,
      this.botCanvas2,
      this.kittenCanvas,
      this.waitBadge,
      this.miniGrid,
      this.shelfBadge,
      this.countdown,
      this.agentDrops.el,
      this.focusDotBig,
      this.focusDotSecond,
    );

    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.greetingCanvas.width = Math.round(EXPANDED_W * dpr);
    this.greetingCanvas.height = Math.round(150 * dpr);
    this.greetingCanvas.style.width = `${EXPANDED_W}px`;
    this.greetingCanvas.style.height = "150px";
    this.kittenCanvas.width = Math.round(KITTEN_W * dpr);
    this.kittenCanvas.height = Math.round(KITTEN_H * dpr);
    this.kittenCanvas.style.width = `${KITTEN_W}px`;
    this.kittenCanvas.style.height = `${KITTEN_H}px`;

    this.root.append(this.wakeStrip, this.islandEl);
    this.applyGeometry();
    this.syncGlow();
  }

  // ── FSM ─────────────────────────────────────────────────────────────────────

  private wireFsm() {
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    this.fsm.openOnHover = State.settings.openOnHover;
    this.fsm.tuckAway = State.settings.tuckAway;
    // Live changes (a pill starts or stops working or waiting) reach the timer through the state: it is written only when it changes.
    State.subscribe(() => this.fsm.setLive(isLive(State.tasks.map((t) => t.state))));
    this.fsm.onTransition = (from, to) => {
      switch (to) {
        case "hidden":
          this.setMode("hidden");
          break;
        case "petit":
          if (from === "hello") this.greeting.interrupt();
          else if (from === "hidden") Sound.play("peek");
          this.setMode("compact");
          if (from === "hello") State.view = State.defaultView();
          if (!this.wasInIsland) this.fsm.mouseLeft();
          break;
        case "home":
          this.expand(State.defaultView());
          if (!this.wasInIsland) this.fsm.mouseLeft();
          break;
        case "hello":
          this.expand("greeting");
          this.greeting.start(State.cast.greeting, State.outfit);
          break;
      }
      // The launch greeting is over, however it ended (it ran out, the pointer left, an alert or a click opened the island): a cat that was out flies back out. The greeting's own
      // onComplete fires only for an undisturbed run; `launch()` is a no-op the second time, and for a cat that is home.
      if (from === "hello") this.desktop?.afterGreeting();
      State.notify();
    };
  }

  launch() {
    this.fsm.launch();
  }

  // ── Mode / view ─────────────────────────────────────────────────────────────

  private setMode(mode: IslandMode) {
    const prev = State.mode;
    if (mode === prev) return;
    State.mode = mode;
    this.syncGlow();
    this.syncPointerWatch();
    // Folded, the peeks are let go with the section that holds them (views/projects.ts leaveAllPeeks).
    if (mode !== "expanded") leaveAllPeeks();
    if (mode !== "hidden") Hub.sk?.islandOpened();
    if (mode === "expanded") Sound.play("open");
    if (prev === "expanded") {
      Sound.play("close");
      State.isPinned = false;
      void Bridge.focusWindow(false);
    }
    if (mode !== "expanded") {
      // Nothing can be seen of the sequence once the island is shut, and leaving
      // it running would keep the frame loop awake — the island must cost
      // nothing while hidden.
      UploadSeq.deactivate();
    }
    this.updateWindowCollapsed();
    this.animateGeometry(modeOrder(mode) < modeOrder(prev));
    State.notify();
  }

  /** True while the drop sequence owns the island body. */
  private get uploadActive(): boolean {
    return State.mode === "expanded" && UploadSeq.isActive && UPLOAD_VIEWS.has(State.view);
  }

  /** Navigating out of the drop flow ends the sequence, as on macOS. */
  private stopSequenceIfLeaving(view: IslandViewName) {
    if (UploadSeq.isActive && !UPLOAD_VIEWS.has(view)) UploadSeq.deactivate();
  }

  expand(view: IslandViewName) {
    this.stopSequenceIfLeaving(view);
    if (view !== "overview") leaveAllPeeks();
    State.view = view;
    if (State.mode !== "expanded") this.setMode("expanded");
    else this.animateGeometry(false);
    State.lastActivity = performance.now();
    this.homeCollapseAt = null;
    State.notify();
  }

  setView(view: IslandViewName) {
    this.stopSequenceIfLeaving(view);
    // A peek belongs to the overview's left card: a view that is not the overview lets it go (views/projects.ts leaveAllPeeks).
    if (view !== "overview") leaveAllPeeks();
    if (State.mode !== "expanded") {
      this.fsm.forceHome();
      State.view = view;
      this.animateGeometry(false);
      State.notify();
      return;
    }
    const grew = VIEW_LAYOUTS[view].height >= VIEW_LAYOUTS[State.view].height;
    State.view = view;
    State.lastActivity = performance.now();
    this.animateGeometry(!grew);
    State.notify();
  }

  /** "Open terminal": the project folder in VS Code. The chat's button and a Sidekick note both go through here. */
  private openTerminalIn(cwd: string | null) {
    void Bridge.openInVSCode(cwd);
  }

  /** The primary action of a card about one agent: the Claude app for a session from it, the project in VS Code for any other (core/openagent.ts). None where there is no app to open. */
  private openAgent(pillId: string | null | undefined, cwd: string | null) {
    const act = finishedAction(pillId, State.claudeApp, State.claudeAppHost);
    if (act === null) return;
    if (act.kind === "claude-app") void Bridge.openClaudeApp();
    else this.openTerminalIn(cwd);
  }

  collapse() {
    State.isPinned = false;
    this.fsm.pinned = false;
    // Drive the state machine rather than the mode: setting the mode behind its
    // back left it thinking the island was still open, and a click on the compact
    // island then did nothing — the island could never be reopened.
    this.fsm.forcePetit();
  }

  /** Rust reads the mouse buttons on every poll tick only while this is on: the island is expanded and the OS has a global pointer (the outside click). Nothing runs on the page for it. */
  private syncPointerWatch() {
    const on = this.cursorPoll && State.mode === "expanded";
    if (on === this.watchingButtons) return;
    this.watchingButtons = on;
    if (!on) this.outside.reset();
    void Bridge.watchPointerButtons(on);
  }

  /** A mouse button went down or came up (Rust `pointer-button`): the outside click's input. */
  onPointerButton(e: ButtonEvent) {
    if (!this.watchingButtons) return;
    this.outside.onButton(e);
  }

  /** What is true when a button goes down, for the outside click's rule (the Mac's counterpart is IslandWindowController.handleOutsideClick). */
  private outsideContext(e: ButtonEvent): OutsideContext {
    const field = document.activeElement;
    return {
      expanded: State.mode === "expanded",
      pinned: State.isPinned,
      held: this.fsm.held || this.fsm.menuOpen,
      typing: State.view === "prompt" && document.hasFocus() && (field instanceof HTMLTextAreaElement || field instanceof HTMLInputElement),
      pointerInIsland: e.own || this.hitRectContains(e.x, e.y),
      busy: this.press.active || this.dragOut.active || State.fileDragOver || this.uploadActive,
    };
  }

  // ── The wings step aside (island/wing.ts; the Mac's counterpart is IslandWindowController.pollFrame) ──────────────────────────────

  /** Which wing of the compact island the point (window px) is in, if any. The zones are the island at rest, never the shrunk one. */
  private wingZone(x: number, y: number): WingZone | null {
    return zoneOf(wings(this.islandRect(), NOTCH_W, HIT_MARGIN), x, y);
  }

  /** Whether the island can step aside now: compact, and nothing wants it (the Mac's `wingAlert`). */
  private wingActive(): boolean {
    const alert = State.pendingApproval !== null || this.fsm.held || State.isPinned || this.fsm.menuOpen || State.fileCatch() || this.dragOut.active
      || (this.desktop?.awayFromHome ?? false) || State.desktopNotchEmpty;
    return wingIsActive(State.mode === "compact", this.greetingShown(), this.press.active, alert);
  }

  /** Asks the rules with the pointer at (x, y). Where the OS gives no global pointer (Wayland) the wings stay put. */
  private feedWing(x: number, y: number): WingOut {
    if (!this.cursorPoll) return this.wing.feed(null, false);
    const active = this.wingActive();
    const zone = active ? this.wingZone(x, y) : null;
    this.fsm.pointerOnWing = zone !== null;
    return this.wing.feed(zone, active);
  }

  /** The rules look at state the cursor does not carry (an alert arriving, the island leaving the compact mode): ask again with the pointer's last place. */
  private refreshWing() {
    this.feedWing(State.mouse.x, State.mouse.y);
  }

  /** The island folded or came back: spring the swoosh, and, when this did not come from a cursor event, run the pointer's enter and leave again (the Mac does it on the same poll tick). */
  private onWingChange(now: WingOut) {
    this.swoosh.springTo(now.faded ? 1 : 0, SPRING_RESPONSE, SPRING_DAMPING);
    this.ensureRunning();
    State.notify();
    if (!this.inCursor) this.onCursor(State.mouse.x, State.mouse.y);
  }

  /** The swoosh and the cats' fade, a frame at a time. Both belong to the compact island: any other mode puts them back at once. */
  private stepWing(dt: number, nowMs: number) {
    if (State.mode !== "compact") {
      if (this.swoosh.value !== 0 || this.swoosh.animating) this.swoosh.jump(0);
      this.wingFade = 1;
      return;
    }
    this.swoosh.step(dt, nowMs);
    this.wingFade = stepFade(this.wingFade, this.wing.state.faded, dt);
  }

  /** The pointer is over the island (the Sidekick does not swap a nicer sentence in under it). */
  get pointerInside(): boolean {
    return this.wasInIsland;
  }

  /** A one-off face from the big cat (the Sidekick's surprised look at a high-risk request). */
  emote(name: BotEmoteName): void {
    this.engine.triggerEmote(name);
  }

  /** Alert from the hook server: open on this view. Pinned alerts never auto-close. */
  alert(view: IslandViewName) {
    this.fsm.pinned = State.isPinned;
    this.fsm.forceHome();
    this.expand(view);
  }

  reveal() {
    this.fsm.reveal();
  }

  /** A waiting chat card holds the island open against the delayed collapse (and a link's card, through LinkIslandHost). */
  holdOpen() {
    this.fsm.pinned = true;
  }

  /** An alert stopped waiting for an answer: let the island auto-close again. */
  dropPin() {
    this.fsm.pinned = false;
  }

  // ── File drop ───────────────────────────────────────────────────────────────

  /** The agent whose cat is under a point of the page (or the pointer's last position): one of the chips shown while a file is dragged. */
  private agentUnder(position?: { x: number; y: number }): string | null {
    const p = dropPoint(position, window.devicePixelRatio || 1, { x: State.mouse.x, y: State.mouse.y });
    return agentCatAt(p.x, p.y, this.agentDrops.targets());
  }

  /**
   * A file was dropped on an agent's cat: its path goes to the clipboard, the agent's project is brought forward where the system lets it (Windows: the "Open terminal" action;
   * Linux: nothing), the agent's cat is happy, and one line says what happened. Nothing is pasted, typed or sent, no session is touched, and the line never says "sent".
   */
  private handoff(agentId: string, paths: string[] | undefined) {
    const text = pathsText(paths, platformName());
    const show = (line: string) => {
      State.noteMessage = line;
      this.setView("note");
      window.setTimeout(() => {
        if (State.view === "note" && State.noteMessage === line) this.setView(State.defaultView());
      }, 2400);
    };
    if (text === null) {
      show(NOT_COPIED_LINE);
      return;
    }
    void Bridge.copyText(text).then((ok) => {
      if (!ok) {
        show(NOT_COPIED_LINE);
        return;
      }
      if (platformName() === "windows") {
        if (openRoute(agentId, State.claudeApp, State.claudeAppHost) === "claude-app") void Bridge.openClaudeApp();
        else void Bridge.openInVSCode(State.tasks.find((t) => t.id === agentId)?.sessionCwd ?? null);
      }
      emoteMiniBots(agentId, "happy");
      show(copiedLine(agentId));
    });
  }

  private onDragDrop(e: { type: string; paths?: string[]; position?: { x: number; y: number } }) {
    if (e.type !== "over") void Bridge.log(`drag ${e.type} ${e.paths?.length ?? 0} file(s)`);
    if (State.paused) return;
    // An item dragged out of the shelf and dropped back on the island is not a new drop, and the drop view must not open under the drag.
    if (this.dragOut.blocks(performance.now())) return;
    switch (e.type) {
      case "enter":
      case "over": {
        this.noteDragPosition(e.position);
        if (State.fileDragOver) return;
        State.fileDragOver = true;
        // enterZone must run before the island expands, so the sequence is
        // already active by the time the view becomes `upload`.
        UploadSeq.enterZone(State.mouseInIsland.x, State.mouseInIsland.y);
        this.uploadCanvas.hover(true);
        this.alert("upload");
        // A chip for each running agent a path could be handed to, in every display mode.
        this.agentDrops.show(dropAgents(State.tasks, State.cast, Hub.sk?.ledger.live.map((s) => s.agentId) ?? []));
        break;
      }
      case "leave": {
        if (!State.fileDragOver) return;
        this.agentDrops.hide();
        State.fileDragOver = false;
        State.dropZone = null;
        // The island deliberately stays open: the drag session is still alive.
        UploadSeq.exitZone();
        this.dragPos = null;
        this.uploadCanvas.hover(false);
        State.notify();
        break;
      }
      case "drop": {
        // A drop on an agent's own cat is tested first, before every other drop rule; the big cat is never one of them. Anywhere else the drop is the one the island always had.
        const agent = this.agentUnder(e.position);
        this.agentDrops.hide();
        if (agent !== null) {
          State.fileDragOver = false;
          State.dropZone = null;
          this.dragPos = null;
          UploadSeq.exitZone();
          this.uploadCanvas.hover(false);
          this.handoff(agent, e.paths);
          break;
        }
        // The half the pointer is in decides (shelf/dropflow.ts, the contract's zoneAt). Ask is today's drop, line for line; Shelf takes all the files and never waits for the desktop cat.
        this.noteDragPosition(e.position);
        const plan = planDrop(this.zoneNow(), e.paths);
        State.fileDragOver = false;
        State.dropZone = null;
        if (plan.kind === "none") {
          this.setView(State.defaultView());
          return;
        }
        // The drop is decided: the position belongs to this drag, and the next one starts without it.
        this.dragPos = null;
        if (plan.kind === "shelf") {
          this.shelfDrop(plan.paths);
          return;
        }
        const path = plan.path;
        this.whenCatIsHere(() => this.swallow(path));
        break;
      }
    }
  }

  /** Where the OS has no global cursor the pointer is the drag event's position; the pointer's half follows it. */
  private noteDragPosition(position: { x: number; y: number } | undefined) {
    this.dragPos = position ?? this.dragPos;
    this.trackZone();
    // The agent chip under the pointer lights up: over events, and the drop path after its own agent test (no chip there).
    this.agentDrops.hover(this.agentUnder(position));
  }

  /** The half of the open island the pointer is in now (null outside it). */
  private zoneNow(): Zone | null {
    const rect = this.islandRect();
    return dropZone({ cursorPoll: this.cursorPoll, polledX: State.mouseInIsland.x, position: this.dragPos, scale: window.devicePixelRatio || 1, islandX: rect.x }, rect.w);
  }

  /** While files are dragged over the island the hot half follows the pointer; only a change is announced. */
  private trackZone() {
    const zone = State.fileDragOver ? this.zoneNow() : null;
    if (zone === State.dropZone) return;
    State.dropZone = zone;
    State.notify();
  }

  /**
   * The shelf opens: from the tray's item, the badge, a drop on the Shelf half. A hidden island comes up on it (an explicit act of the user, never the shelf's own doing). Whether
   * the originals are still there is looked at now, and only now.
   */
  openShelf() {
    void State.shelf.refresh();
    this.alert("shelf");
  }

  /** The Projects screen opens: from a "+N" cell, or the header's tab. A hidden island comes up on it, as the shelf's does. */
  openProjects() {
    this.alert("projects");
  }

  /**
   * Ask, from a shelf tile: the file goes to the chat the way a drop on Ask does. The drop view opens with the file already over it, the desktop cat (if out) is waited for as for
   * any drop, and the catch plays; Rust copies the file into the inbox from the shelf's id (the page holds no path), and the chat starts new with it.
   */
  private askShelf(id: string) {
    const entry = State.shelf.entries.find((e) => e.id === id);
    if (!entry || !State.shelf.canAsk(id)) return;
    UploadSeq.enterZone(USC.REST_X, USC.REST_Y);
    this.uploadCanvas.hover(true);
    this.setView("upload");
    this.whenCatIsHere(() => this.swallow(entry.name, () => Bridge.shelfAsk(id)));
  }

  /**
   * Drags these shelf items out of the island, to anywhere (Explorer, the file manager, mail, a chat). The island stays open while the drag lasts, and a drop that comes back to it is
   * ignored (`dragOut`). Rust finds the files from the ids and carries them with the system's own drag (dragout.rs).
   */
  private dragOutShelf(ids: string[]) {
    if (!State.shelfCaps.dragOut || this.dragOut.active || ids.length === 0) return;
    this.dragOut.start();
    this.fsm.setShelfHold("drag", true);
    Bridge.shelfDragOut(ids)
      .catch((err) => void Bridge.log(`drag out failed: ${String(err)}`))
      .finally(() => {
        this.dragOut.end(performance.now());
        this.fsm.setShelfHold("drag", false);
        State.notify();
      });
  }

  /** Send, through the system's Share window (Windows). The island stays open a little while the window comes up; what the user picks in it is the system's. */
  private sendShelf(ids: string[]) {
    if (!State.shelfCaps.send || ids.length === 0) return;
    this.sendHold.start();
    Bridge.shelfSend(ids)
      .catch(() => void Bridge.log("send failed"))
      .finally(() => this.sendHold.finish());
  }

  /** Show in Explorer or the file manager. */
  private revealShelf(id: string) {
    Bridge.shelfReveal(id).catch(() => {});
  }

  /** Whether the OS has a global cursor (Boot's `cursorPoll`). */
  setCursorPoll(on: boolean) {
    this.cursorPoll = on;
    this.syncPointerWatch();
  }

  /**
   * Files dropped on the Shelf half (sub-project G1). The drop takes a fresh token, so an Ask drop still waiting for the desktop cat never runs and never clears this alert, and an Ask
   * file still being copied shows no note over the shelf. It does not wait for the desktop cat and nothing catches it: the upload sequence stops, the file alert is over
   * (`State.fileCatch` is false once the flow is left, so the desktop cat goes back by its normal rule), and the island shows the shelf.
   */
  private shelfDrop(paths: string[]) {
    this.catchTurn++;
    this.dropCount++;
    this.dropWaiting = false;
    UploadSeq.deactivate();
    this.uploadCanvas.hover(false);
    this.setView("shelf");
    void State.shelf.add(paths).catch(() => {
      console.warn("shelf add failed");
    });
    this.shelfDropToken = this.dropCount;
    State.notify();
  }

  /**
   * A file was dropped. If the desktop cat is out it is flying to the notch to catch it (a file on its way in is an alert to it: `State.fileCatch`), and the catch waits for it, at most
   * `DESKTOP_CATCH_WAIT_MS`, so the island never draws a second cat. With the cat home it runs at once. A short chain of timeouts that exists only for the length of one drop: no interval.
   * `dropWaiting` keeps the alert on meanwhile (`State.fileDragOver` is already false), so the cat does not turn round.
   */
  private whenCatIsHere(run: () => void) {
    const t0 = performance.now();
    const turn = ++this.catchTurn;
    this.dropWaiting = true;
    let waited = false;
    const wait = () => {
      if (State.desktopNotchEmpty && performance.now() - t0 < DESKTOP_CATCH_WAIT_MS) {
        waited = true;
        window.setTimeout(wait, 50);
        return;
      }
      // A superseded drop never clears the newer drop's alert.
      const latest = turn === this.catchTurn;
      if (latest) this.dropWaiting = false;
      // With the cat home nothing waited and nothing is checked: the drop runs at once, as before the wait. After a wait, only the latest drop whose flow is still open runs
      // (a newer drop or leaving the flow ends this one, and nothing is written or played: as FileDropView on macOS).
      if (!waited || (latest && this.uploadActive)) {
        run();
        return;
      }
      // The latest drop whose flow closed during its wait: clear its drag state and notify, so the desktop cat does not stay at the notch until the next change.
      if (latest) {
        State.fileDragOver = false;
        State.notify();
      }
    };
    wait();
  }

  /**
   * The cat eats the file. Nothing here waits on the file system: the copy into
   * the inbox runs in the background and swaps the path in when it lands, so a
   * slow disk can never stall the animation — same as FileDropHandler on macOS.
   */
  private swallow(path: string, ingest: (path: string) => Promise<DroppedFile> = (p) => Bridge.ingestFile(p)) {
    const name = path.split(/[\\/]/).pop() || "file";
    // A drop while the chat is in its own window: the window goes first (its conversation is already saved), and the new conversation starts here in the island.
    if (State.chatPoppedOut) {
      void Bridge.hideChatWindow();
      State.chatPoppedOut = false;
    }
    State.droppedFile = { name, path };
    State.promptContext = { kind: "file", name, path };
    State.pendingAttachment = null;
    State.dropReader = null;
    State.chatHistory = [];
    State.localAnswers = [];
    State.chatEpoch++;
    // A drop starts a new conversation, which is not saved yet (its id is made by the first save).
    State.chatId = null;
    // A new chat: a new Claude Code session at Chat only. Whatever it was waiting to do is refused.
    releaseChatApprovals();
    State.resetClaude();
    void Bridge.chatReset();

    UploadSeq.performDrop(State.uploadDuration);
    this.uploadCanvas.drop(name);
    const drop = ++this.dropCount;
    this.uploadTens = 0;
    this.uploadDone = false;

    this.engine.triggerEmote("happy");

    State.uploadProgress = 0;
    this.setView("uploading");
    this.ensureRunning();

    void ingest(path)
      .then(async (file) => {
        // A Shelf drop came after this Ask drop: the shelf is on screen, so this copy plays no chime and attaches nothing.
        if (drop <= this.shelfDropToken) return;
        // The file is taken: now the approve chime. A refused file never gets it.
        Sound.play("approve");
        // A newer drop of any kind (another Ask) owns the attachment: this copy keeps its chime but attaches nothing.
        if (drop !== this.dropCount) return;
        State.droppedFile = { name: file.name, path: file.path };
        State.promptContext = { kind: "file", name: file.name, path: file.path };
        // The inbox copy goes with the next message, whichever turn that is.
        State.pendingAttachment = file.path;
        State.notify();
        const reader = await Bridge.aiResolve("files");
        State.dropReader = reader?.reader ?? null;
        State.notify();
      })
      .catch((err) => {
        // A newer drop owns the view and its state now: a stale failure shows no note and clears nothing of it.
        if (drop !== this.dropCount) return;
        forgetDrop(State);
        const { message, refused } = classifyIngestError(err);
        const showNote = () => {
          UploadSeq.deactivate();
          State.noteMessage = message;
          this.setView("note");
          const sound = noteSound(refused); // none after a refusal: the cat's annoyed already played, as it started to gag
          if (sound) Sound.play(sound);
          // A drop inside the 2.4 s (a shelf drop, or another note) replaces this note: this timer closes only the note of its own drop.
          const shown = this.dropCount;
          window.setTimeout(() => { if (State.view === "note" && this.dropCount === shown) this.setView(State.defaultView()); }, 2400);
        };
        if (!refused) {
          showNote();
          return;
        }
        // The app refuses this file (an app, an archive, a disk image, a video, over 25 MB). The cat caught it like any other: now it
        // gags and coughs it up as a hairball (`annoyed` once, as the gag starts), and the note comes after it, silent. No check mark, no approve chime.
        // The user left the drop flow, or dropped again, while the ingest was pending: this refusal is over, and must not touch the new drop.
        if (drop !== this.dropCount || !UploadSeq.isActive) return;
        UploadSeq.refuse();
        this.uploadCanvas.refuse();
        const arrives = Math.max(0, FLIGHT_MS / 1000 - (UploadSeq.sinceDrop() ?? 0));
        window.setTimeout(() => {
          // Leaving the drop flow in the meantime, or a new drop, has already ended this refusal.
          if (drop === this.dropCount && UploadSeq.refused) showNote();
        }, (arrives + HAIRBALL_S) * 1000);
      });
  }

  /**
   * Sounds and view changes hung off the canvas timeline: a `tick` every 10 %,
   * the ✓ chime when the bar completes, then `choose` once the cat has grown back.
   */
  private stepSequence() {
    const since = UploadSeq.sinceDrop();
    if (since == null || UploadSeq.refused) return;
    const dur = State.uploadDuration;
    const p = Math.max(0, Math.min(1, (since - PRE_PROGRESS) / dur));

    const tens = Math.floor(p * 10);
    if (tens > this.uploadTens && tens < 10) {
      this.uploadTens = tens;
      Sound.play("tick");
    }

    if (!this.uploadDone && since >= PRE_PROGRESS + dur) {
      this.uploadDone = true;
      Sound.play("approve");
      this.engine.triggerEmote("happy");
    }
    // The extra second is the grow-back, after which the choose card is up.
    if (since >= PRE_PROGRESS + dur + 1 && State.view === "uploading") {
      this.setView("choose");
    }
  }

  // ── Geometry ────────────────────────────────────────────────────────────────

  private targetSize(): { w: number; h: number; r: number } {
    const { w, h } = islandSize(State.mode, State.view, State.chatHistory.length + State.localAnswers.length, State.sidekickNote?.lines.length ?? 1, State.projectsNow().panelShown ? PANEL_EXTRA : 0);
    const r = State.mode === "expanded" ? EXPANDED_CORNER : ROUNDED_CORNER;
    return { w, h, r };
  }

  private animateGeometry(shrinking: boolean) {
    const { w, h, r } = this.targetSize();
    if (shrinking) {
      this.width.curveTowards(w);
      this.height.curveTowards(h);
      this.radius.curveTowards(r);
    } else {
      this.width.springTo(w);
      this.height.springTo(h);
      this.radius.springTo(r);
    }
    this.ensureRunning();
  }

  private applyGeometry() {
    // The wings (island/wing.ts): `full` is the island as it would be at rest, `w` what is drawn, narrowed towards the notch-wide middle by the swoosh. The hover zones and the pointer keep using `full`.
    const full = this.width.value;
    const swoosh = State.mode === "compact" ? this.swoosh.value : 0;
    const w = swoosh === 0 ? full : widthAt(full, NOTCH_W, swoosh);
    const hh = this.height.value;
    const r = this.radius.value;
    this.islandEl.style.width = `${w}px`;
    this.islandEl.style.height = `${hh}px`;
    this.islandEl.style.borderRadius = `0 0 ${r}px ${r}px`;
    this.islandEl.style.transform = `translateX(-50%)`;
    // These follow the island as it resizes, so they belong here rather than in
    // the state-driven DOM sync.
    this.miniGrid.style.left = `${w - 40 - 14.5}px`;
    this.miniGrid.style.top = `${hh / 2 - 14.5}px`;
    const badge = badgePlace(w, hh);
    this.shelfBadge.style.left = `${badge.left}px`;
    this.shelfBadge.style.top = `${badge.top}px`;
    this.waitBadge.style.left = `${badge.left}px`;
    this.waitBadge.style.top = `${badge.top}px`;
    this.greetingCanvas.style.left = `${(w - EXPANDED_W) / 2}px`;
    this.uploadCanvas.el.style.left = `${(w - EXPANDED_W) / 2}px`;
    this.zones.el.style.left = `${(w - EXPANDED_W) / 2}px`;

    // Click-through follows the pointer's zone, not the drawn width: folded, only the notch-wide middle takes the mouse (from the tick the fold starts), otherwise the island as it would be at rest.
    const rect = this.wing.state.faded && State.mode === "compact" ? foldedHitRect(viewportWidth(), hh, NOTCH_W, HIT_MARGIN) : { x: (viewportWidth() - full) / 2, y: 0, w: full, h: hh };
    // The cats, the grid and the badge fade with the fold: a CSS variable the stylesheet multiplies into their opacity (style.css "The wings step aside").
    this.islandEl.classList.toggle("wing-on", State.mode === "compact" && this.wingFade < 1);
    this.islandEl.style.setProperty("--nm-wing", String(this.wingFade));
    const p = this.pushedRect;
    if (Math.abs(p.x - rect.x) > 0.5 || Math.abs(p.w - rect.w) > 0.5 || Math.abs(p.h - rect.h) > 0.5) {
      this.pushedRect = rect;
      void Bridge.setIslandRect(rect.x, rect.y, rect.w, rect.h);
    }
  }

  /** Island rect in window coordinates (origin top-left of the 720×600 window). */
  private islandRect(): { x: number; y: number; w: number; h: number } {
    const w = this.width.value;
    const hh = this.height.value;
    return { x: (viewportWidth() - w) / 2, y: 0, w, h: hh };
  }

  /** Whether a point (window coordinates) is over the island, with the hit margin: what the cursor poll calls "in the island". */
  private hitRectContains(x: number, y: number): boolean {
    const rect = this.islandRect();
    return x >= rect.x - HIT_MARGIN && x <= rect.x + rect.w + HIT_MARGIN && y >= rect.y - HIT_MARGIN && y <= rect.y + rect.h + HIT_MARGIN;
  }

  /** The hover glow: the class `glow` while Settings → Hover glow is on, `hovered` while the pointer is over a shown island. The CSS does the rest (style.css). */
  private syncGlow() {
    this.islandEl.classList.toggle("glow", State.settings.hoverGlow);
    this.islandEl.classList.toggle("hovered", State.settings.hoverGlow && this.wasInIsland && State.mode !== "hidden");
  }

  // ── Window collapse (hidden → tiny wake strip, zero polling) ────────────────

  private updateWindowCollapsed() {
    if (this.collapseTimer != null) {
      window.clearTimeout(this.collapseTimer);
      this.collapseTimer = null;
    }
    if (State.mode === "hidden") {
      // Let the island finish retracting, then drop the window to the wake strip:
      // from there the OS delivers no cursor events, so nothing polls at all.
      this.collapseTimer = window.setTimeout(() => {
        this.collapseTimer = null;
        if (State.mode !== "hidden") return;
        this.collapsed = true;
        void Bridge.setCollapsed(true);
      }, 420);
    } else if (this.collapsed) {
      // Grow the window back before the island animates open.
      this.collapsed = false;
      void Bridge.setCollapsed(false);
    }
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  private wireInput() {
    // The wake strip is the only thing the OS can hit while the island is hidden.
    this.wakeStrip.addEventListener("mouseenter", (e) => {
      Sound.resume();
      if (State.mode === "hidden") {
        // Only a pointer inside the poll's hit rect counts as over the island: the strip is wider than it, and an entry in its outer band would be reported as a leave by the next move.
        if (this.fsm.openOnHover && this.hitRectContains(e.clientX, e.clientY)) {
          // Open on hover only: the open that follows the dwell reads where the pointer is, and with no cursor poll (Linux) a stationary pointer would still count as outside
          // and start the 0.6 s fold over itself. The enter edge's own events fire here, since the poll will not see an edge for this hover.
          this.wasInIsland = true;
          this.sleep.event("hover");
          Hub.sk?.noteHovered();
        }
        this.fsm.mouseEntered();
      }
    });

    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      this.sleep.event("click");
      State.lastActivity = performance.now();
      // A click makes a hover-opened island an ordinary open one; only the primary button counts as a click for the tuck-away count.
      this.fsm.userInteracted(e.button === 0);
      // The big cat can be dragged out of the notch (sub-project H): a press on it is a click or a drag, decided when the button comes up.
      const x = e.clientX, y = e.clientY;
      // A right press on a big cat opens its menu (the contextmenu event below) instead of acting as a click. Every other press is as it was.
      if (e.button === 2 && this.onBigCat(x, y)) return;
      if (e.button === 0 && this.desktop?.canCarry && !State.desktopNotchEmpty && State.mode !== "hidden" && !this.greetingShown() && !this.uploadActive && this.isBotHit(x, y)) {
        this.press.press(x, y);
        this.pressAction = () => this.pressed(x, y);
        return;
      }
      this.pressed(x, y);
    });
    // Right-click on a big cat (sub-project I): a native menu with only Wardrobe in it. Anywhere else the page keeps what it did.
    this.islandEl.addEventListener("contextmenu", (e) => {
      if (!this.onBigCat(e.clientX, e.clientY)) return;
      e.preventDefault();
      void this.showWardrobeMenu();
    });
    // A move with the primary button up means the release was lost (the window lost the capture): it ends the press there, once.
    window.addEventListener("mousemove", (e) => ((e.buttons & 1) === 0 ? this.carryUp(e.clientX, e.clientY) : this.carryMove(e.clientX, e.clientY)));
    window.addEventListener("mouseup", (e) => this.carryUp(e.clientX, e.clientY));
    // The left wing's dwell must know whether a mouse button is held (island/wing.ts): a press cancels it, the release starts it over. While the window takes the mouse the page's own events say so.
    const buttons = (e: MouseEvent) => {
      const down = e.buttons !== 0;
      if (down === this.mouseButtonDown) return;
      this.mouseButtonDown = down;
      this.wing.poke();
    };
    window.addEventListener("mousedown", buttons, true);
    window.addEventListener("mouseup", buttons, true);
    window.addEventListener("mousemove", buttons, true);

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && State.mode === "expanded" && !State.isPinned) this.collapse();
      State.lastActivity = performance.now();
    });

    void onDragDrop((e) => this.onDragDrop(e));

    // Outside Tauri (plain browser) drive the cursor from DOM events so the
    // island can be inspected with `npm run dev`.
    if (!IS_TAURI) this.followPageCursor();
  }

  /** A point of the island window is on a big cat the island is showing: the main cat, or cat 2 in Two cats mode (cat/menuhit.ts). */
  private onBigCat(x: number, y: number): boolean {
    return wardrobeMenuHit(x, y, { mode: State.mode, greeting: this.greetingShown(), upload: this.uploadActive, desktopOut: State.desktopNotchEmpty, bot: this.botCircle(), bot2: this.cast.second?.pill ? this.bot2Circle() : null });
  }

  /** A project pill's Pin menu, built once and reused like the Wardrobe menu: its one item says Pin or Unpin for the project the menu was opened on. */
  private projectMenu: Promise<PinMenu> | null = null;
  /** The pending release of the Pin menu's hold (500 ms after it closes), kept so the next menu can clear it. */
  private projectMenuRelease: number | null = null;
  private menuTarget = "";

  /**
   * A row's click, and a project's through its newest session: the approval card when that session owns the card on the notch, else the session's app. A terminal session
   * has no app of its own here, so it opens in VS Code like the Claude pill's ↗ (openRoute). The folder is read here only, for the jump.
   */
  private jumpToSession(sessionId: string): void {
    if (State.pendingApproval?.sessionId === sessionId) {
      this.setView("approval");
      return;
    }
    const row = State.projectsNow().view.projects.flatMap((p) => p.sessions).find((s) => s.id === sessionId);
    if (!row) return;
    const route = openRoute("integration_claude", State.claudeApp, row.host === "claude-app");
    if (route === "claude-app") void Bridge.openClaudeApp();
    else if (route === "vscode") void Bridge.openInVSCode(State.projects.cwdOf(sessionId));
  }

  /** The Pin menu of a project pill, opened by its right-click. Outside Tauri the pin is toggled at once. The island is held while the menu is open, as for Wardrobe. */
  private async showProjectMenu(id: string): Promise<void> {
    if (!IS_TAURI) {
      State.projects.togglePin(id);
      State.notify();
      return;
    }
    this.menuTarget = id;
    // An earlier menu's release must not release this one's hold: a pending release goes now, and this menu takes its own hold below.
    if (this.projectMenuRelease !== null) {
      window.clearTimeout(this.projectMenuRelease);
      this.projectMenuRelease = null;
      this.fsm.menuHold(false, this.wasInIsland);
    }
    this.projectMenu ??= buildPinMenu(() => {
      State.projects.togglePin(this.menuTarget);
      State.notify();
    });
    let parts: PinMenu;
    try { parts = await this.projectMenu; } catch { this.projectMenu = null; console.error("[notchmeow] pin menu failed"); return; }
    this.fsm.menuHold(true, this.wasInIsland);
    try {
      await parts.item.setText(pinTitle(State.projects.isPinned(id)));
      await parts.menu.popup();
    } catch {
      // A menu that cannot be shown or set is dropped: the next right-click builds it again. Never the error's text.
      console.error("[notchmeow] pin menu failed");
      this.projectMenu = null;
    } finally {
      // The release waits a little: the click that chose the item must not fold the island under the pointer (P-mac).
      this.projectMenuRelease = window.setTimeout(() => {
        this.projectMenuRelease = null;
        this.fsm.menuHold(false, this.wasInIsland);
      }, PIN_MENU_RELEASE_MS);
      if (!this.wasInIsland && this.fsm.state === "home" && !State.isPinned) this.homeCollapseAt = performance.now() + State.settings.autoCloseInterval * 1000;
    }
  }

  /** The island cat's right-click menu, built once and reused (a native menu's items are resources in Rust that nothing frees): only Wardrobe for now. */
  private wardrobeMenu: Promise<{ menu: Menu; wardrobe: WardrobeItems }> | null = null;

  private async showWardrobeMenu(): Promise<void> {
    this.wardrobeMenu ??= (async () => {
      const wardrobe = await buildWardrobeItems((id) => this.pickOutfit(id));
      return { menu: await Menu.new({ items: [await Submenu.new({ text: "Wardrobe", items: wardrobe.items })] }), wardrobe };
    })();
    let parts: { menu: Menu; wardrobe: WardrobeItems };
    try { parts = await this.wardrobeMenu; } catch { this.wardrobeMenu = null; return; }
    // The menu holds the island open like a pending card. popup() resolves when the native menu closes on Windows and the Mac (it blocks the main thread); on GTK the popup resolves on open, so the hold ends at once there and the fold runs as before.
    this.fsm.menuHold(true, this.wasInIsland);
    try {
      await tickWardrobe(parts.wardrobe, State.settings.cat.outfit);
      await parts.menu.popup();
    } finally {
      this.fsm.menuHold(false, this.wasInIsland);
      if (!this.wasInIsland && this.fsm.state === "home" && !State.isPinned) this.homeCollapseAt = performance.now() + State.settings.autoCloseInterval * 1000;
    }
  }

  /** A pick of the island cat's Wardrobe submenu: the same choice as Settings → Wardrobe, stored once and applied at once. */
  private pickOutfit(id: OutfitId): void {
    State.settings.cat = withOutfit(State.settings.cat, id);
    void Bridge.saveSettings(State.settings);
    this.wardrobe.sync();
  }

  /** What a press on the island does: a click on the compact island opens it; in the open island a press slaps the big cat or focuses the second cat's agent. */
  private pressed(x: number, y: number) {
    if (State.mode !== "expanded") {
      this.fsm.click();
      return;
    }
    // Two cats: a click on the second cat focuses its agent, as a click on a pill does.
    const second = this.cast.second;
    const hit = catClickTarget(x, y, this.botCircle(), second?.pill ? this.bot2Circle() : null);
    if (hit === 2 && second?.pill) {
      State.setFocus(second.pill);
      Sound.play("blip");
      return;
    }
    // The big cat is not in the notch while it is out: nothing to slap at its empty spot (sub-project H).
    if (hit === 1 && !State.desktopNotchEmpty) {
      this.cancelBotHover();
      this.engine.slap();
    }
  }

  /** The pointer moved with a press on the big cat: past 4 px it is a drag, and the cat is carried out of the notch by it (the window follows it, across the screen). */
  private carryMove(x: number, y: number) {
    const step = this.press.move(x, y);
    if (step === "start") this.desktop?.carryStart();
    if (step) this.desktop?.carry(x, y);
  }

  /** The button came up: a press that never moved far is the click it always was; the end of a drag puts the cat down (or back in the notch when it is dropped on it). */
  private carryUp(x: number, y: number) {
    const r = this.press.release(), act = this.pressAction;
    this.pressAction = null;
    if (r === "click") act?.();
    else if (r === "drop") {
      this.desktop?.carryEnd(x, y, this.overNotch(x, y));
    }
  }

  /** A point of the island window is over the island (with the hit margin): a cat put down there goes home. */
  private overNotch(x: number, y: number): boolean {
    const rect = this.islandRect();
    return x >= rect.x - HIT_MARGIN && x <= rect.x + rect.w + HIT_MARGIN && y >= rect.y - HIT_MARGIN && y <= rect.y + rect.h + HIT_MARGIN;
  }

  /** The desktop cat's brain (island/desktop.ts), made by main.ts once the screens are known. */
  attachDesktop(brain: DesktopBrain) { this.desktop = brain; }

  /** What the desktop cat needs of the island. A click on the desktop cat opens the island the way the tray's Open does. */
  desktopHost(): DesktopHost {
    return {
      open: () => this.alert(State.defaultView()),
      wake: (kind) => this.noteActivity(kind),
      notchLocal: () => notchCatLocal(State.mode, State.view, !!this.cast.second),
      overNotch: (x, y) => this.overNotch(x, y),
      outfitChanged: () => this.wardrobe.sync(),
    };
  }

  /**
   * Takes the cursor from the page's own mouse events instead of Rust's poll.
   * Used where the OS has no global cursor position (Wayland): the events only
   * fire while the pointer is over the island, so leaving the window is
   * reported as a cursor far away, which is what the poll would have said.
   */
  followPageCursor() {
    window.addEventListener("mousemove", (e) => this.onCursor(e.clientX, e.clientY));
    window.addEventListener("mouseout", (e) => {
      if (e.relatedTarget == null) this.onCursor(-10_000, -10_000);
    });
  }

  /** An agent event, a hover or a click: wakes a sleeping cat and starts its ten minutes again (island/sleep.ts). The hook handlers call it for every event. */
  noteActivity(kind: "hook" | "hover" | "click") {
    this.sleep.event(kind);
  }

  /** A hook event or an alert reached the island (hooks.ts): the tuck-away count starts again, and a compact island that is up re-arms its timer. */
  agentActivity(): void {
    this.fsm.agentActivity();
  }

  /** Cursor in window-logical coordinates. */
  onCursor(x: number, y: number, down?: boolean) {
    this.inCursor = true;
    if (down !== undefined) this.mouseButtonDown = down;
    State.mouse = { x, y };
    // While a file is dragged the cursor poll goes on: the chip of the agent whose cat is under it lights up.
    if (State.fileDragOver) this.agentDrops.hover(agentCatAt(x, y, this.agentDrops.targets()));
    const rect = this.islandRect();
    State.mouseInIsland = { x: x - rect.x, y: y - rect.y };

    // Windows sends no cursor position with an OLE drag, so the drop sequence is
    // fed from the Win32 cursor poll instead — it runs throughout the drag.
    if (UploadSeq.isActive && !UploadSeq.dropped) {
      UploadSeq.updateCursor(State.mouseInIsland.x, State.mouseInIsland.y);
      this.trackZone();
    }

    // The wings step aside: over either wing of the compact island the whole island folds into the notch-wide middle, and the pointer there is not on the island.
    const wasOnWing = this.fsm.pointerOnWing;
    const wing = this.feedWing(x, y);
    const inIsland = this.hitRectContains(x, y) && !wing.passThrough;

    if (inIsland && !this.wasInIsland) {
      this.sleep.event("hover");
      Hub.sk?.noteHovered();
      if (this.fsm.state === "hello") this.greeting.hover();
      this.fsm.mouseEntered();
      this.homeCollapseAt = null;
    }
    if (!inIsland && this.wasInIsland) {
      this.fsm.mouseLeft();
      if (this.fsm.state === "home" && !State.isPinned && !this.fsm.menuOpen) {
        this.homeCollapseAt = performance.now() + (this.fsm.openedByHover ? this.fsm.hoverCloseDelay : State.settings.autoCloseInterval) * 1000;
      }
    }
    // The pointer came off a wing into the middle while still over the island: no enter edge, so Open on hover's dwell is armed again here.
    if (inIsland && this.wasInIsland && wasOnWing && !this.fsm.pointerOnWing) this.fsm.hoverResume();
    this.wasInIsland = inIsland;
    this.syncGlow();
    this.inCursor = false;

    // Bot hover → love
    const overBot = State.mode === "expanded" && State.stateOverride == null && !State.desktopNotchEmpty && this.isBotHit(x, y);
    if (overBot && !this.botHovering) this.botHoverIn(x, y);
    if (!overBot && this.botHovering) this.cancelBotHover();
    this.botHovering = overBot;
    if (this.botHovering) {
      const d = Math.hypot(x - this.botHoverStart.x, y - this.botHoverStart.y);
      if (d > 40) {
        this.botHoverStart = { x, y };
        this.scheduleLove();
      }
    }

    this.ensureRunning();
  }

  private bot2Circle(): Circle | null {
    if (!this.pairShown) return null;
    const rect = this.islandRect();
    return { cx: rect.x + this.bot2Cx.value, cy: rect.y + this.bot2Cy.value, r: this.bot2Size.value / 2 };
  }

  private botCircle(): Circle {
    const rect = this.islandRect();
    return { cx: rect.x + this.botCx.value, cy: rect.y + this.botCy.value, r: this.botSize.value / 2 };
  }

  /** A press on the big cat (a drag out of the notch, the love hover). In Two cats mode a press in cat 2's part of the overlap is cat 2's: it is not on the big cat. */
  private isBotHit(x: number, y: number): boolean {
    return bigCatPressed(x, y, this.botCircle(), this.cast.second?.pill ? this.bot2Circle() : null);
  }

  private botHoverIn(x: number, y: number) {
    if (performance.now() / 1000 - this.lastLoveTime < 6) return;
    this.botHoverStart = { x, y };
    this.engine.blink();
    this.engine.tgEs = 1.08;
    Sound.play("hover");
    this.scheduleLove();
  }

  private scheduleLove() {
    if (this.botHoverTimer != null) window.clearTimeout(this.botHoverTimer);
    this.botHoverTimer = window.setTimeout(() => {
      this.botHoverTimer = null;
      if (!this.botHovering || State.stateOverride != null) return;
      if (performance.now() / 1000 - this.lastLoveTime < 6) return;
      this.lastLoveTime = performance.now() / 1000;
      this.engine.triggerEmote("love");
      Sound.play("love");
    }, 1900);
  }

  private cancelBotHover() {
    if (this.botHoverTimer != null) window.clearTimeout(this.botHoverTimer);
    this.botHoverTimer = null;
    this.engine.tgEs = 1;
  }

  /** Three slaps → dizzy + confused view for 3.3 s, then back. */
  private handleDizzy() {
    this.prevViewBeforeConfused = State.view;
    State.stateOverride = "dizzy";
    this.engine.setState("dizzy");
    Sound.play("dizzy");
    this.alert("confused");
    if (this.confusedRecovery != null) window.clearTimeout(this.confusedRecovery);
    this.confusedRecovery = window.setTimeout(() => {
      this.confusedRecovery = null;
      State.stateOverride = null;
      this.engine.setState(this.bigLook().state);
      if (State.view === "confused") {
        const fallback = State.defaultView();
        this.setView(this.prevViewBeforeConfused === "confused" ? fallback : this.prevViewBeforeConfused);
      }
      this.engine.triggerEmote("happy");
    }, 3300);
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────

  /**
   * The greeting canvas is up in the expanded island, and then, after the island has folded, through the compact island's tail: the row of
   * session cats pops in and glides into the grid there. The canvas draws its own cat and cats meanwhile; the real ones take over at the end.
   */
  private greetingShown(): boolean {
    return greetingShown(State.mode, State.view, this.greeting.live);
  }

  ensureRunning() {
    if (this.running) return;
    this.running = true;
    this.lastFrame = performance.now();
    requestAnimationFrame(this.frame);
  }

  private frame = (nowMs: number) => {
    const dt = Math.min(0.05, (nowMs - this.lastFrame) / 1000);
    this.lastFrame = nowMs;
    this.cast = State.cast;
    // Only the expanded island reads the projects frame per frame (the big card, its peek, its kittens); folded, syncDom's refresh is enough.
    if (State.mode === "expanded") this.projectsFrame = State.projectsNow();

    this.width.step(dt, nowMs);
    this.height.step(dt, nowMs);
    this.radius.step(dt, nowMs);
    this.stepWing(dt, nowMs);
    this.applyGeometry();

    if (this.dirty) {
      this.dirty = false;
      this.syncDom();
    }

    this.updateBotTargets();
    this.botCx.step(dt);
    this.botCy.step(dt);
    this.botSize.step(dt);
    this.bot2Cx.step(dt);
    this.bot2Cy.step(dt);
    this.bot2Size.step(dt);
    this.placeFocusDots();

    const greetingActive = this.greetingShown();
    if (greetingActive) {
      const gctx = this.greetingCanvas.getContext("2d");
      if (gctx) {
        const dpr = Math.min(2, window.devicePixelRatio || 1);
        gctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        this.greeting.draw(gctx);
      }
    } else {
      // Kept running even while the drop canvas is up, so the island's own cat
      // is already in the right place the moment the canvas fades out.
      if (!State.desktopNotchEmpty) this.drawBot(dt);
      if (this.pairShown) this.drawBot2(dt);
    }

    const uploadActive = this.uploadActive;
    if (uploadActive) this.uploadCanvas.draw(UploadSeq.frame(), nowMs / 1000);
    this.uploadCanvas.el.classList.toggle("on", uploadActive);
    this.zones.sync(uploadActive && State.fileDragOver, State.dropZone);
    this.viewsEl.classList.toggle("hidden-by-upload", uploadActive);

    this.drawKittenLayer(dt, greetingActive || this.peeking());
    tickMiniBots(dt);
    tickKittenStrips(dt);
    this.views.get(State.view)?.tick?.(nowMs);
    if (UploadSeq.isActive) this.stepSequence();
    this.updateCountdown(nowMs);

    // Nothing is drawn while the island is hidden, so nothing may keep the loop
    // alive either. This used to read `... || this.engine.busy || State.mode !==
    // "hidden"`, and engine.busy is permanently true for any state with a
    // looping animation — breathing, ratelimit sweat, sleeping z's, the search
    // sweep — so a hidden island went on burning frames in exactly the states it
    // spends most of its life in. Geometry still has to finish retracting.
    const settling =
      this.width.animating || this.height.animating || this.radius.animating || this.swoosh.animating || this.wingFade !== (this.wing.state.faded ? 0 : 1);
    const busy = State.mode === "hidden"
      ? settling
      : settling ||
        !this.botCx.settled || !this.botCy.settled || !this.botSize.settled ||
        greetingActive || this.engine.busy || UploadSeq.isActive ||
        (this.pairShown && (this.engine2.busy || !this.bot2Cx.settled || !this.bot2Cy.settled || !this.bot2Size.settled));

    if (busy) {
      requestAnimationFrame(this.frame);
    } else {
      this.running = false;
      Sound.idle();
    }
  };

  /** The compact notch's two amber dots sit 0.42 of each cat's diameter from its centre, up and to the right (the Mac's FocusWaitCompactDots). Placed each frame as the springs move. */
  private placeFocusDots() {
    if (State.mode !== "compact") return;
    this.focusDotBig.style.left = `${this.botCx.value + this.botSize.value * 0.42 - 2.5}px`;
    this.focusDotBig.style.top = `${this.botCy.value - this.botSize.value * 0.42 - 2.5}px`;
    this.focusDotSecond.style.left = `${this.bot2Cx.value + this.bot2Size.value * 0.42 - 2.5}px`;
    this.focusDotSecond.style.top = `${this.bot2Cy.value - this.bot2Size.value * 0.42 - 2.5}px`;
  }

  private updateBotTargets() {
    // Two cats: the pair's places (compact, and the overview); anywhere else the first cat is where it always was and the second is not drawn.
    const pair = this.cast.second ? pairPlacement(State.mode, State.view, this.height.value) : null;
    const p = pair ? pair.first : botPosition(State.mode, State.view, this.height.value, State.uploadProgress);
    this.botCx.target = p.cx;
    this.botCy.target = p.cy;
    this.botSize.target = p.diameter / 0.6;

    const greetingActive = this.greetingShown();
    // The drop canvas draws its own cat; two of them would overlap.
    const visible = p.opacity > 0 && !greetingActive && !this.uploadActive;
    // The desktop cat has left the big cat's spot (sub-project H): nothing of it is drawn in the notch, and cat 2 and the pills stay.
    this.botCanvas.style.opacity = visible && !State.desktopNotchEmpty ? "1" : "0";
    // A project's peek covers the big cat: it steps aside while the peek shows (sub-project P).
    if (this.peeking()) this.botCanvas.style.opacity = "0";
    this.pairShown = pair !== null && visible;
    if (pair) {
      this.bot2Cx.target = pair.second.cx;
      this.bot2Cy.target = pair.second.cy;
      this.bot2Size.target = pair.second.diameter / 0.6;
    }
    this.botCanvas2.style.opacity = this.pairShown ? "1" : "0";

    if (State.mode === "expanded" && State.view !== "uploading" && !greetingActive && !this.uploadActive && !State.desktopNotchEmpty) {
      const d = p.diameter;
      const glow = this.bigLook().state;
      const color = botGlowColor(glow);
      // A project's peek covers the cat, so its glow steps aside with it (IslandRootView.swift, sub-project P).
      this.botGlow.style.display = this.peeking() ? "none" : "block";
      this.botGlow.style.width = `${d * 2.2}px`;
      this.botGlow.style.height = `${d * 2.2}px`;
      this.botGlow.style.left = `${this.botCx.value - d * 1.1}px`;
      this.botGlow.style.top = `${this.botCy.value - d * 1.1}px`;
      this.botGlow.style.background = `radial-gradient(circle, ${color} 0%, transparent 62%)`;
      this.botGlow.style.opacity = String(botGlowOpacity(glow));
    } else {
      this.botGlow.style.display = "none";
    }
  }

  private drawBot(dt: number) {
    const size = this.botSize.value;
    const w = Math.max(1, Math.round(size));
    const hCss = w + BOT_OVERHANG;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.canvasPx !== w) {
      this.canvasPx = w;
      this.botCanvas.width = Math.round(w * dpr);
      this.botCanvas.height = Math.round(hCss * dpr);
      this.botCanvas.style.width = `${w}px`;
      this.botCanvas.style.height = `${hCss}px`;
    }
    this.botCanvas.style.left = `${this.botCx.value - w / 2}px`;
    this.botCanvas.style.top = `${this.botCy.value - BOT_OVERHANG / 2 - hCss / 2}px`;

    const ctx = this.botCanvas.getContext("2d");
    if (!ctx) return;

    const focus = State.focusTask;
    const look = this.bigLook();
    this.engine.setCoat(look.coat);
    this.engine.collarColor = bigCatCollar(look.state, focus?.color);
    this.engine.outfit = State.outfit; // a big cat in every size, the compact notch's included (sub-project I)
    this.engine.particleOverhang = BOT_OVERHANG;
    this.engine.badgeLeft = State.mode === "compact";
    // The top of the compact strip is the top of the screen, so the ears are fitted under it: the room above the cat's centre is botCy.
    this.engine.earRoom = State.mode === "compact" ? this.botCy.value : null;
    this.engine.setDancing(shouldDance(State.musicPlaying, look.state, State.mode));
    this.engine.lookX = this.lookX();
    this.engine.lookY = this.lookY();
    this.engine.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hCss);
    this.engine.draw(ctx, w, hCss);
  }

  /**
   * The subagent kittens of the big cat and, in Two cats mode, of the second cat (kittens.ts places them; kittendraw.ts draws them): compact, up to two tucked beside the cat
   * (one cat, a cat for each agent) or a count by the pair; expanded, in the overview, a row of up to three under each cat. They stay out of every other expanded view, where
   * the cards' text would run under them. Nothing draws while the greeting or the drop sequence owns the island; the canvas is cleared once when the last kitten goes.
   */
  private drawKittenLayer(dt: number, covered: boolean) {
    const ctx = this.kittenCanvas.getContext("2d");
    if (!ctx) return;
    const expanded = State.mode === "expanded", cast = this.cast, now = performance.now();
    const shown = !covered && State.mode !== "hidden" && !this.uploadActive && (!expanded || State.view === "overview");
    const big = shown && cast.big.pill && !State.desktopNotchEmpty ? State.kittenView(cast.big.pill, now) : [], second = shown && cast.second?.pill ? State.kittenView(cast.second.pill, now) : [];
    // The Claude-only card's big cat wears the big card's project's subagents (sub-project P); every other view keeps the line above.
    const proj = shown && expanded && !State.desktopNotchEmpty ? this.projectsThisFrame() : null;
    const projBig = proj?.usesProjects && proj.big ? proj.big : null;
    const bigList = projBig ? projectKittens(projBig.sessions.flatMap((s) => s.subagents)) : big;
    if (!bigList.length && !second.length) {
      if (this.kittensDrawn) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, this.kittenCanvas.width, this.kittenCanvas.height); this.kittensDrawn = false; }
      return;
    }
    this.kittensDrawn = true;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, KITTEN_W, KITTEN_H);
    // The compact kittens fade out as the island opens and the expanded ones fade in as it is nearly open. (The cats' own drawing sets the canvas's alpha, so the fade is the canvas's.)
    const grow = clamp((this.height.value - NOTCH_H) / (VIEW_LAYOUTS.overview.height - NOTCH_H), 0, 1);
    this.kittenCanvas.style.opacity = String(expanded ? seg(grow, 0.55, 1) : 1 - seg(grow, 0, 0.25));
    const place = kittenPlaceOf(cast.mode, expanded), colorOf = (pill: string | null) => State.tasks.find((t) => t.id === pill)?.color ?? null;
    const D = this.botSize.value * 0.6, D2 = this.bot2Size.value * 0.6;
    if (place === "pairCompact") {
      // No room beside two Ø20 cats: a count of both cats' kittens by the second cat.
      drawKittens(ctx, this.kittenPool, { place, pill: cast.big.pill ?? "", parentCat: cast.big.cat, color: null, ox: this.bot2Cx.value, oy: this.bot2Cy.value, unit: D2 }, [...bigList, ...second], dt);
    } else {
      const bigSpot = projBig ? { pill: projBig.id, parentCat: projBig.cat, color: CLAUDE_COLOR } : { pill: cast.big.pill ?? "", parentCat: cast.big.cat, color: colorOf(cast.big.pill) };
      if (bigList.length) drawKittens(ctx, this.kittenPool, { place, ...bigSpot, ox: this.botCx.value, oy: this.botCy.value, unit: D }, bigList, dt);
      if (second.length && cast.second) drawKittens(ctx, this.kittenPool, { place, pill: cast.second.pill ?? "", parentCat: cast.second.cat, color: colorOf(cast.second.pill), ox: this.bot2Cx.value, oy: this.bot2Cy.value, unit: D2 }, second, dt);
    }
    this.kittenPool.endFrame();
  }

  /** The second cat of Two cats mode: the pair's second coat, showing the busiest other agent (idle, with no badge, when there is none). */
  private drawBot2(dt: number) {
    const size = this.bot2Size.value;
    const w = Math.max(1, Math.round(size));
    const hCss = w + BOT_OVERHANG;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.canvas2Px !== w) {
      this.canvas2Px = w;
      this.botCanvas2.width = Math.round(w * dpr);
      this.botCanvas2.height = Math.round(hCss * dpr);
      this.botCanvas2.style.width = `${w}px`;
      this.botCanvas2.style.height = `${hCss}px`;
    }
    this.botCanvas2.style.left = `${this.bot2Cx.value - w / 2}px`;
    this.botCanvas2.style.top = `${this.bot2Cy.value - BOT_OVERHANG / 2 - hCss / 2}px`;
    const ctx = this.botCanvas2.getContext("2d");
    const second = this.cast.second;
    if (!ctx || !second) return;
    const task = second.pill ? State.tasks.find((t) => t.id === second.pill) : undefined;
    const state = State.shownState(task?.state ?? "idle");
    this.engine2.setCoat(second.cat);
    this.engine2.setState(state);
    this.engine2.collarColor = bigCatCollar(state, task?.color);
    this.engine2.outfit = State.outfit; // cat 2 is a big cat too
    this.engine2.particleOverhang = BOT_OVERHANG;
    this.engine2.badgeLeft = State.mode === "compact";
    this.engine2.earRoom = State.mode === "compact" ? this.bot2Cy.value : null;
    this.engine2.setDancing(shouldDance(State.musicPlaying, state, State.mode));
    const rect = this.islandRect();
    this.engine2.lookX = cursorLook(State.mouse.x - (rect.x + this.bot2Cx.value), 0).x;
    this.engine2.lookY = cursorLook(0, State.mouse.y - this.bot2Cy.value).y;
    this.engine2.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hCss);
    this.engine2.draw(ctx, w, hCss);
  }

  /** BotCanvasView.lookX / lookY — tanh of the distance to the bot. */
  private lookX(): number {
    const rect = this.islandRect();
    const botScreenX = rect.x + this.botCx.value;
    return cursorLook(State.mouse.x - botScreenX, 0).x;
  }

  private lookY(): number {
    return cursorLook(0, State.mouse.y - this.botCy.value).y;
  }

  private updateCountdown(nowMs: number) {
    if (State.mode !== "expanded" || State.isPinned || this.homeCollapseAt == null) {
      this.countdown.style.width = "0px";
      return;
    }
    const autoClose = State.settings.autoCloseInterval;
    const windowS = Math.min(10, autoClose * 0.6);
    const remaining = (this.homeCollapseAt - nowMs) / 1000;
    this.countdown.style.width =
      remaining < windowS ? `${Math.max(0, clamp(remaining / windowS, 0, 1) * 160)}px` : "0px";
  }

  // ── DOM sync ────────────────────────────────────────────────────────────────

  /** The big cat's look (sub-project P): the big card's project's coat and state while the Claude-only card's overview is open, else the cast's coat and the effective state. */
  private bigLook(): { coat: string; state: BotStateName } {
    const f = this.projectsThisFrame();
    if (State.mode === "expanded" && State.view === "overview" && f.usesProjects && f.big) {
      return { coat: f.big.cat, state: State.stateOverride ?? State.shownState(f.big.state) };
    }
    return { coat: State.cast.big.cat, state: State.effectiveState };
  }

  /** A project's peek is open: the big cat and its kittens step aside under it (sub-project P). */
  private peeking(): boolean {
    return State.mode === "expanded" && State.view === "overview" && this.projectsThisFrame().peeking !== null;
  }

  /** This animation frame's Projects frame: the cache `frame` and `syncDom` keep, so the big cat, its peek and its kittens read one computation per frame. */
  private projectsThisFrame(): ProjectsFrame {
    return this.projectsFrame ?? State.projectsNow();
  }

  private syncDom() {
    this.refreshWing();
    const expanded = State.mode === "expanded";
    const greetingActive = this.greetingShown();
    // The Projects frame (sub-project P): the section's height follows it on the existing spring.
    const frame = State.projectsNow();
    this.projectsFrame = frame;
    const panelShown = frame.panelShown;
    if (panelShown !== this.panelWasShown) {
      this.panelWasShown = panelShown;
      this.animateGeometry(!panelShown);
    }
    // Hidden, or expanded past the greeting view, before the tail is over: the beat ends here, so a later compact does not resume it.
    if (!greetingActive && State.mode !== "compact") this.greeting.end();

    this.contentEl.style.opacity = expanded && !greetingActive ? "1" : "0";
    this.contentEl.style.pointerEvents = expanded && !greetingActive ? "auto" : "none";
    // Not display: none, so that the canvas fades out over its last frame (it is not redrawn) while the real cat and grid fade in.
    this.greetingCanvas.style.transition = greetingActive ? "none" : "opacity 0.25s ease-in-out";
    this.greetingCanvas.style.opacity = greetingActive ? "1" : "0";

    this.header.sync();
    for (const [name, view] of this.views) {
      const on = name === State.view;
      view.el.classList.toggle("on", on);
      if (on) view.sync();
    }

    // The chat is the only view with a text field, so it is the only time the
    // island is allowed to take keyboard focus.
    if (this.lastSyncedView !== State.view) {
      const wasChat = this.lastSyncedView === "prompt";
      this.lastSyncedView = State.view;
      if (State.view === "prompt") {
        void Bridge.focusWindow(true);
        window.setTimeout(() => this.views.get("prompt")?.focus?.(), 120);
      } else if (wasChat) {
        void Bridge.focusWindow(false);
      }
    }

    // Compact mini grid
    const showGrid = State.mode === "compact" && !greetingActive;
    this.miniGrid.style.opacity = showGrid ? "1" : "0";
    if (showGrid) {
      const row = State.pillRow;
      const key = row.map(({ task }) => `${task.id}:${State.focusDot(task.id) ? 1 : 0}`).join("|");
      if (this.miniGrid.dataset.key !== key) {
        this.miniGrid.dataset.key = key;
        this.miniGrid.replaceChildren();
        for (const { task, cat } of row) {
          const slot = createMiniBot(task, 13, cat);
          if (State.focusDot(task.id)) slot.append(h("i", { class: "fa-mini-dot" }));
          this.miniGrid.append(slot);
        }
        pruneMiniBots();
      }
    }
    // The compact dots (focus awareness): the big cat's and cat 2's, each shown while the grid shows and its pill is waiting.
    this.focusDotBig.style.opacity = showGrid && State.cast.big.pill && !State.desktopNotchEmpty && State.focusDot(State.cast.big.pill) ? "1" : "0";
    this.focusDotSecond.style.opacity = showGrid && this.pairShown && State.cast.second?.pill && State.focusDot(State.cast.second.pill) ? "1" : "0";

    // The shelf's badge: a function of the mode and the count. Nothing here opens, reveals or expands the island (shelf/badge.ts).
    // The waiting count (sub-project P) takes the badge's place while a session waits: waiting first, the shelf's count after it.
    const showWait = badgeShown(State.mode, frame.view.waiting, greetingActive);
    const showBadge = badgeShown(State.mode, State.shelf.count, greetingActive) && !showWait;
    this.shelfBadge.style.opacity = showBadge ? "1" : "0";
    this.shelfBadge.style.pointerEvents = showBadge ? "auto" : "none";
    this.shelfBadge.textContent = badgeLabel(State.shelf.count);
    this.shelfBadge.title = shelfBadgeTitle(State.shelf.count);
    this.waitBadge.style.opacity = showWait ? "1" : "0";
    this.waitBadge.style.pointerEvents = showWait ? "auto" : "none";
    this.waitBadge.textContent = badgeLabel(frame.view.waiting);
    this.waitBadge.title = badgeTitle(frame.view.waiting);
    // The one tick: only while the island is open with a live project (projects/clock.ts); nothing else moves the states without an event.
    this.projectsTick.sync(State.mode === "expanded" && frame.view.projects.length > 0);

    syncMiniBotStates(State.tasks);
    this.engine.setState(this.bigLook().state);
  }

  /** The Settings window changed a preference: the chat reads its model again, so the cloud line follows the brain the user picked. */
  settingsChanged() {
    void this.views.get("prompt")?.refreshModel?.();
  }

  /** Applies settings coming from Rust at boot. */
  applySettings() {
    Sound.setEnabled(State.settings.soundEnabled);
    Sound.setVolume(State.settings.soundVolume);
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    this.fsm.openOnHover = State.settings.openOnHover;
    this.fsm.tuckAway = State.settings.tuckAway;
    this.syncGlow();
    // The cat block comes from Rust already clean; cleaning it again costs nothing and keeps a bad value out of every engine. The Display settings stay in it: it is saved back whole.
    const block = cleanCatBlock(State.settings.cat);
    applyCatSettings(catCfg, block);
    State.settings.cat = block;
    this.wardrobe.sync();
    State.notify();
  }

  get panelSize() {
    return { w: PANEL_W, h: PANEL_H };
  }

  get chatHeight() {
    return chatPromptHeight(State.chatHistory.length + State.localAnswers.length);
  }
}
