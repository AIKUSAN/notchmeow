// App state — mirror of AppState.swift (the parts the island needs).

import type { Feature } from "./bridge";
import type { ClaudeChatLevel, ClaudeStatus, ClaudeStep, Payer } from "./claude";
import { ApprovalQueue } from "./claude.ts";
import type { BotStateName, IslandMode, IslandViewName } from "./layout";
import { assignAgentCats } from "../cat/agentcat.ts";
import { castOf } from "../cat/cast.ts";
import type { Cast } from "../cat/cast.ts";
import { defaultCatBlock } from "../cat/display.ts";
import type { CatBlock } from "../cat/display.ts";
import type { OutfitId } from "../cat/wardrobe.ts";
import { kittenStep, kittenView } from "../cat/kittens.ts";
import type { Kitten, KittenEvent } from "../cat/kittens.ts";
import { cleanSidekickSettings } from "../sidekick/core.ts";
import type { SidekickSettings } from "../sidekick/core.ts";
import { cleanCompanionSettings } from "../companion/core.ts";
import type { CompanionSettings } from "../companion/core.ts";
import { contextOf } from "../companion/turn.ts";
import type { QuickResult } from "../companion/quick.ts";
import type { TurnContext } from "../companion/turn.ts";
import type { Note } from "../sidekick/notes.ts";
import type { LocalAnswer } from "../sidekick/statuschat.ts";
import { ShelfStore } from "../shelf/store.ts";
import { LinkStore } from "../link/model.ts";
import type { Zone } from "../shelf/rules.ts";
import type { TuckChoice } from "../island/tuckaway.ts";
import { agentColor, agentPillName } from "./pills.ts";
import { ProjectsModel } from "../projects/model.ts";
import type { ProjectsFrame } from "../projects/model.ts";
import { endMarks, markForPill, recordMark, showsDot } from "./focusaware.ts";
import type { FocusMark, ForegroundKind } from "./focusaware.ts";

export type AgentSource = "claudeCode" | "n8n" | "agent";
export type PillBadge = "approval" | "finished" | "error";

export interface AgentTask {
  id: string;
  name: string;
  color: string;
  state: BotStateName;
  stepIndex: number;
  steps: string[];
  source: AgentSource;
  isIntegration: boolean;
  pillBadge?: PillBadge | null;
  sessionCwd?: string | null;
  /** The time of this pill's last hook event (ms, `performance.now()`): it decides the busiest other agent in Two cats mode. Missing until the pill's first event. */
  last?: number;
}

export interface ApprovalInfo {
  requestId: string;
  sessionId: string;
  /** The pill of the agent that asked (its ID: `integration_claude`, `agent_<tag>`). A click on the card is recorded against it. */
  pillId: string;
  tool: string;
  command: string;
  /** The subagent that asked (the hook's `agent_id`), when one did: its kitten waits on an approval until this one is answered. */
  agentId?: string;
  /** The Sidekick's reading of the request (sub-project F1): the basename it names (a file, or empty), how risky it looks, and one fixed sentence saying why. Missing when it was not read. */
  target?: string;
  risk?: "low" | "medium" | "high";
  line?: string;
}

/** What a button under a chat note does — mirrors errors::Action in Rust. */
export type AiAction =
  | { kind: "openSettings" }
  | { kind: "openBilling"; url: string }
  | { kind: "openGuide" }
  | { kind: "chooseModel" }
  | { kind: "cancel" }
  | { kind: "signInClaude" }
  | { kind: "installClaude" }
  | { kind: "updateClaude" }
  | { kind: "installGit" }
  | { kind: "tryAgain" };

export interface ChatSource {
  url: string;
  title: string;
}

export interface ChatMessage {
  id: number;
  /** `note`: a line from NotchMeow itself (an error, a countdown), not from the model. */
  role: "user" | "assistant" | "note";
  content: string;
  /** User messages: the inbox files this message was sent with. A conversation that holds one keeps using the File questions setting (`featureFor`). */
  attachments?: readonly string[];
  /** Under a reply: "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b". */
  caption?: string;
  /** Web-search sources, shown as links under the reply. */
  sources?: ChatSource[];
  /** Lines under the reply: a cut file, trimmed history, a fallback. */
  notices?: string[];
  /** `interrupted`: the stream broke; `stopped`: Stop was pressed. */
  status?: "streaming" | "interrupted" | "stopped";
  /** The one button a note may carry. */
  action?: AiAction | null;
  /** Under a reply: the setting that answered, so Continue and Retry use it again. */
  feature?: Feature;
  /** Steps Claude Code took for this reply (reading a file, running a command), shown as rows above it. */
  steps?: ClaudeStep[];
}

export type PromptContext =
  | { kind: "window"; appName: string; title: string; url?: string }
  | { kind: "file"; name: string; path?: string };

export interface ResultItem {
  label: string;
  detail: string;
  url?: string;
}

export interface SearchResult {
  title: string;
  items: ResultItem[];
  note?: string;
}

const task = (
  id: string, name: string, color: string, source: AgentSource,
): AgentTask => ({
  id, name, color, state: "idle", stepIndex: 0, steps: [], source, isIntegration: true,
});

/** AgentTask.integrationAgents — same ids, names and colours as macOS. */
export const INTEGRATION_AGENTS: AgentTask[] = [
  task("integration_claude", "Claude Code", "#F5F6F8", "claudeCode"),
  task("integration_resend", "Resend", "#22C55E", "n8n"),
  task("integration_n8n", "n8n", "#F29B38", "n8n"),
  task("integration_vercel", "Vercel", "#7C5CFF", "n8n"),
  task("integration_github", "GitHub", "#F4505E", "n8n"),
  task("integration_notion", "Notion", "#8C8C8C", "n8n"),
  task("integration_calcom", "Cal.com", "#C9956A", "n8n"),
  task("integration_stripe", "Stripe", "#0570DE", "n8n"),
];

export const TOGGLEABLE_INTEGRATION_IDS = [
  "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
  "integration_notion", "integration_calcom", "integration_stripe",
];

/** The agents that can be switched on in Settings: an agent switched on stays on the island (the Mac's rule), as an agent switched off is transient. `tag` is the relay tag (windows/hook/src/agents.rs). */
export const AGENT_SWITCHES: readonly { id: string; tag: string }[] = [
  { id: "agent_gemini", tag: "gemini" },
  { id: "agent_antigravity", tag: "antigravity" },
];

/** What an integration poller last reported. */
export interface IntegrationInfo {
  data: Record<string, unknown>;
  error: string | null;
  loaded: boolean;
  configured: boolean;
}

/** "auto", or one model on one provider. */
export type ModelChoice = "auto" | { provider: string; model: string };

/** The AI part of settings.json — mirrors settings::AiSettings in Rust. */
export interface AiSettings {
  chat: ModelChoice;
  files: ModelChoice;
  /** Which cloud Auto tries first. */
  preferredCloud: "claudeCode" | "anthropic" | "openai";
  /** Remembered model per cloud provider. */
  cloudModels: Record<string, string>;
  /** Last-used model per local server. */
  localModels: Record<string, string>;
  lastUsedLocal: { provider: string; model: string } | null;
  /** The server added with "Add server…". */
  customServer: string | null;
  /** The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in. */
  claudeCodeEnabled: boolean;
  /** Claude Code's model alias for the chat. */
  claudeCodeModel: "sonnet" | "opus" | "haiku";
}

export const DEFAULT_AI: AiSettings = {
  chat: "auto",
  files: "auto",
  preferredCloud: "anthropic",
  cloudModels: {},
  localModels: {},
  lastUsedLocal: null,
  customServer: null,
  claudeCodeEnabled: false,
  claudeCodeModel: "sonnet",
};

export interface Settings {
  soundEnabled: boolean;
  soundVolume: number;
  autoCloseInterval: number;
  /** Hovering the island opens it all the way (off: hovering only peeks). */
  openOnHover: boolean;
  /** A soft rainbow halo along the island's outline while the pointer is over it. */
  hoverGlow: boolean;
  /** Step back when I'm already in the app (focus awareness), on by default. */
  focusAware: boolean;
  /** When the compact island hides by itself: "never" (the default), or the minutes of quiet once nothing is live (island/tuckaway.ts, as on the Mac). */
  tuckAway: TuckChoice;
  activeIntegrations: string[];
  screen: "primary" | "cursor";
  autostart: boolean;
  hooksInstalled: boolean;
  /** Which models answer (settings::AiSettings). */
  ai: AiSettings;
  /**
   * The `cat` block of Settings, clean (cat/display.ts): the Cat settings (the Main cat, the motion style, the collar, the fur lines and each cat's own motion, collar and
   * personality) and the Display settings (the mode, the pair and the agents' coats).
   */
  cat: CatBlock;
  /**
   * The Sidekick (sub-project F1), clean (sidekick/settings.ts): the master switch "Recaps and nudges", the local-wording switch and how often each kind of note was
   * dismissed (two mute it). The permission line and the risk badge have no switch.
   */
  sidekick: SidekickSettings;
  /**
   * The Companion (sub-project F3a), clean (companion/core.ts `cleanCompanionSettings`): the humor, the memory and sessions switches, the recap's polish, how often
   * the daily recap was dismissed, its last day, and the cloud providers that have had their one-time notice. The Rust twin keeps the `companion` block of settings.json.
   */
  companion: CompanionSettings;
}

export const DEFAULT_SETTINGS: Settings = {
  soundEnabled: true,
  soundVolume: 0.12,
  autoCloseInterval: 15,
  openOnHover: false,
  hoverGlow: true,
  focusAware: true,
  tuckAway: "never",
  activeIntegrations: [
    "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
  ],
  screen: "primary",
  autostart: false,
  hooksInstalled: false,
  ai: { ...DEFAULT_AI },
  cat: defaultCatBlock(),
  sidekick: cleanSidekickSettings(null),
  companion: cleanCompanionSettings(null),
};

type Listener = () => void;

class AppState {
  mode: IslandMode = "hidden";
  view: IslandViewName = "overview";

  tasks: AgentTask[] = [];
  focusId: string | null = null;

  stateOverride: BotStateName | null = null;

  /** The cats are asleep: ten minutes with no agent event, hover or click (island/sleep.ts). An idle cat then shows `sleeping`; one that is working, asking or finished does not. */
  asleep = false;

  /** The outfit the big cats wear now (sub-project I): the stored choice resolved for today (island/wardrobe.ts), one of the 16 drawn outfit IDs or `none`, never `auto`. Only a big cat gets it. */
  outfit: OutfitId = "none";

  /** The big cat's spot in the notch is empty: the desktop cat has left it (sub-project H). Set by the trip (island/desktop.ts); while it is true the island draws no big cat, glow or kittens for it. */
  desktopNotchEmpty = false;

  /** Music is playing: the cat in the compact island bobs to it (cat/dance.ts). Nothing sets this on Windows and Linux yet: there is no media reader, so it is the seam a later plan fills. */
  musicPlaying = false;

  /** Cursor in logical screen pixels, origin top-left (like AppState.mousePosition). */
  mouse = { x: 0, y: 0 };
  /** Cursor relative to the island's top-left corner. */
  mouseInIsland = { x: 0, y: 0 };

  isPinned = false;
  paused = false;

  uploadProgress = 0;
  uploadDuration = 2.4;
  fileDragOver = false;
  /** Files are dragged over the open drop view: the half the pointer is in (Ask or Shelf), or null outside the island (shelf/dropflow.ts). */
  dropZone: Zone | null = null;
  /**
   * Whether a file is on its way into the island: dragged over it, a drop waiting for the desktop cat, or its drop flow on screen. To the desktop cat that is an alert (cat/desktop.ts
   * `desktopAlert`): it flies in to catch the file and back when the flow is over. The island replaces this with the full rule; until it does, the drag alone counts.
   */
  fileCatch: () => boolean = () => this.fileDragOver;

  promptContext: PromptContext | null = null;
  droppedFile: { name: string; path: string } | null = null;
  /** The inbox copy of the file just dropped: it goes with the next message, then clears. */
  pendingAttachment: string | null = null;
  /** The drop card's "… will read this": "Claude", "Local · qwen3.5:2b". */
  dropReader: string | null = null;
  noteMessage: string | null = null;
  searchResult: SearchResult | null = null;
  chatHistory: ChatMessage[] = [];
  /** NotchMeow's own answers in the chat ("What's Claude doing?", sub-project F1). Never part of `chatHistory`, so never part of the conversation any model is sent. */
  localAnswers: LocalAnswer[] = [];
  /** Bumped whenever the conversation is reset, so a reply still streaming for the old one is ignored. */
  chatEpoch = 0;
  /** The saved conversation the chat is in (its file's id): null until its first reply is saved, and after a new chat or a drop (companion/session.ts). */
  chatId: string | null = null;
  /** When that conversation was first saved (ms). */
  chatCreatedAt = 0;
  /** Whether that conversation is pinned in the list. */
  chatPinned = false;
  /** A title the user gave it; null takes the first message's (titleOf). */
  chatTitle: string | null = null;
  /** The chat is in its own window (companion/windowlink.ts): the island's chat shows only a note and a button, and the island pushes the window its context. */
  chatPoppedOut = false;
  /** The quick card above the chat's field: the last Fix or Rewrite (companion/quick.ts). Memory only; a new chat keeps it, a dismiss clears it. */
  quickResult: QuickResult | null = null;
  pendingApproval: ApprovalInfo | null = null;
  /** The Sidekick's note, for the island's `sidekick` view (sub-project F1): a recap or a nudge. Set by the Sidekick when the gate lets it show; the view keeps showing it until the island moves on. */
  sidekickNote: Note | null = null;

  /** Claude Code: the session ids whose hook events belong to this chat (island/hooks.ts routes by them). */
  claudeSessions = new Set<string>();
  /** What Claude may do in this chat. Every new chat starts at Chat only. */
  claudeLevel: ClaudeChatLevel = { level: "chat", folder: null };
  /** What the last check found of Claude Code; null until one ran. */
  claudeStatus: ClaudeStatus | null = null;
  /** Who paid for the last Claude Code run, as it said itself. */
  claudePaidBy: Payer | null = null;
  /** The steps Claude Code is waiting to take in this chat (Agent level), in the order they asked. */
  chatApprovals = new ApprovalQueue();

  integrations: Record<string, IntegrationInfo> = {};

  lastActivity = performance.now();

  settings: Settings = { ...DEFAULT_SETTINGS };

  /** Each agent pill's subagent kittens (cat/kittens.ts), by pill ID. Never stored: `kittenEvent` is the only way they change and `kittenView` says what to draw. */
  kittens: Record<string, Kitten[]> = {};

  /** The shelf (sub-project G1): what Rust last said, the ticked items and the note after a drop. Empty until main.ts hands it a backend and reads it. */
  shelf = new ShelfStore(() => this.notify());

  /** What this system can do for a shelf item, from Rust's boot info: drag it out of the island, send it through the system's share. Show in folder and Ask always work. */
  shelfCaps = { dragOut: false, send: false };

  /** The link between this machine and the user's others (sub-project G2): what Rust last said, and the backend. Empty until main.ts hands it a backend and reads it. */
  link = new LinkStore(() => this.notify());

  /** An offer from another machine waits for a click: an alert like an approval (the desktop cat flies to the notch for it, island/sleep.ts does not let the cats fall asleep). */
  get linkOfferPending(): boolean {
    return this.link.offerPending;
  }
  /** There is a Claude desktop app the Open button can start (Windows); Anthropic ships none for Linux (core/openagent.ts). */
  claudeApp = false;

  /** The Claude Code pill's last session runs in the Claude desktop app (its relay tag, core/openagent.ts): its ↗ and its finished card open that app. */
  claudeAppHost = false;

  /** What the frontmost app can be read as here (Rust's boot info, focus awareness). "none" turns the feature off on this system. */
  foregroundKind: ForegroundKind = "none";

  /** The focus marks of the sessions that stepped back (memory only, ten minutes each, core/focusaware.ts): the amber dot on a pill and the note on its card. */
  focusMarks: FocusMark[] = [];

  /** A step-back made a mark. No notify here: handleHook notifies after the feed. */
  recordFocusMark(mark: FocusMark): void {
    this.focusMarks = recordMark(this.focusMarks, mark);
  }

  /** A session's event ends its marks (core/focusaware.ts `endMarks`: the own-question twin of --ask does not end them). */
  endFocusMarks(sessionId: string, event: string, tool: string): void {
    this.focusMarks = endMarks(this.focusMarks, sessionId, event, tool);
  }

  /** The amber dot on a pill now: a live mark on it, and no badge or waiting card on the pill (core/focusaware.ts `showsDot`). */
  focusDot(pillId: string, now = Date.now()): boolean {
    const task = this.tasks.find((t) => t.id === pillId);
    return showsDot(markForPill(this.focusMarks, pillId, now) !== null, task?.pillBadge != null, this.pendingApproval?.pillId === pillId);
  }

  /** The Projects registry (sub-project P): memory only. main.ts replaces it once, with the home folder and the skewed clock. */
  projects = new ProjectsModel();

  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */
  rand: () => number = () => Math.random();

  /** Called when a coat was given to an agent and the settings changed: the island saves them (main.ts), so the agent keeps its cat. Null until it is set. */
  persistSettings: (() => void) | null = null;

  private listeners = new Set<Listener>();

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  /** Marks the UI dirty; the island re-renders on the next frame. */
  notify() {
    for (const fn of this.listeners) fn();
  }

  /** A new conversation: a new Claude Code session at Chat only. (Hooks.ts hands back any waiting approval first.) */
  resetClaude() {
    this.claudeSessions.clear();
    this.claudeLevel = { level: "chat", folder: null };
  }

  /** An approval or a question is waiting for the user, in the notch or in a chat: the desktop cat flies to the notch for it (cat/desktoptrip.ts), and the cat never sleeps through it (island/sleep.ts). */
  get attentionNeeded(): boolean {
    return this.pendingApproval !== null || this.chatApprovals.length > 0 || this.tasks.some((t) => t.state === "approval" || t.state === "question");
  }

  get focusTask(): AgentTask | null {
    return this.tasks.find((t) => t.id === this.focusId) ?? this.tasks[0] ?? null;
  }

  get effectiveState(): BotStateName {
    return this.stateOverride ?? this.shownState(this.focusTask?.state ?? "idle");
  }

  /** The state a cat shows for a task state: an idle cat sleeps while the cats are asleep; every other state shows as itself. */
  shownState(state: BotStateName): BotStateName {
    return state === "idle" && this.asleep ? "sleeping" : state;
  }

  fallAsleep() {
    if (this.asleep) return;
    this.asleep = true;
    this.notify();
  }

  /** An event woke the cats. Playful's `enter` starts the waking zoomies when the cat leaves `sleeping`. */
  wake() {
    if (!this.asleep) return;
    this.asleep = false;
    this.notify();
  }

  get otherTasks(): AgentTask[] {
    return this.tasks.filter((t) => t.id !== this.focusId);
  }

  /**
   * The cast of the chosen display mode (cat/cast.ts): which coat the big cat, the second cat, the pills and the grid, the drop view and the greeting wear. It is a pure
   * function of the settings, the pills and the focus, cheap enough to ask once a frame.
   */
  get cast(): Cast {
    const cat = this.settings.cat;
    return castOf(cat.displayMode, {
      tasks: this.tasks.map((t) => ({ id: t.id, state: t.state, last: t.last ?? 0 })),
      focusId: this.focusTask?.id ?? null, mainCat: cat.character, pair: cat.pair, agentCats: cat.agentCats,
    });
  }

  /** The pills of the row and of the 2×2 grid, with their coats: the cast's `pills`, at most four (in One cat mode, `otherTasks.slice(0, 4)`; in Two cats mode without the second cat's agent). */
  get pillRow(): { task: AgentTask; cat: string }[] {
    const row: { task: AgentTask; cat: string }[] = [];
    for (const p of this.cast.pills) {
      const task = this.tasks.find((t) => t.id === p.pill);
      if (task) row.push({ task, cat: p.cat });
    }
    return row;
  }

  /** What the companion's turn knows now (F3a-tauri): the Projects view, whether a card is up, the Main cat's mood. Read when a message is sent. */
  contextNow(): TurnContext {
    return contextOf({ view: this.projects.view(), attention: this.attentionNeeded, mood: this.effectiveState });
  }

  /** The Projects frame now (sub-project P): the live projects, the big card, the layout, the panel and the peek, computed from the registry at this moment (no timer moves the time-based states). */
  projectsNow(): ProjectsFrame {
    return this.projects.frame({
      projectCats: this.settings.cat.projectCats, mainCat: this.settings.cat.character,
      activePills: [...this.settings.activeIntegrations, ...this.tasks.map((t) => t.id)],
      open: this.mode === "expanded",
      focusId: this.focusId,
      twoCats: this.cast.second !== null,
    });
  }

  /** A hook event reached this pill: it is the pill's last event now (ms, `performance.now()`). An ID that has no pill is ignored. */
  noteEvent(id: string, t: number = performance.now()) {
    const task = this.tasks.find((x) => x.id === id);
    if (task) task.last = t;
  }

  /** Gives the agent pills in `ids` (default: every pill) the cat they have not got yet (cat/agentcat.ts), and keeps it: a new random coat is stored in the settings and saved. */
  giveCoats(ids: readonly string[] = this.tasks.map((t) => t.id)) {
    const cat = this.settings.cat, next = assignAgentCats(ids, cat.agentCats, cat.character, this.rand);
    if (JSON.stringify(next) === JSON.stringify(cat.agentCats)) return;
    this.settings.cat = { ...cat, agentCats: next };
    this.persistSettings?.();
  }

  /** A subagent event for this pill (cat/kittens.ts `kittenStep`; island/subagents.ts maps the hooks to events). An ID that has no pill is ignored. */
  kittenEvent(id: string, ev: KittenEvent) {
    if (!this.tasks.some((t) => t.id === id)) return;
    const next = kittenStep(this.kittens[id] ?? [], ev);
    if (next.length) this.kittens[id] = next;
    else delete this.kittens[id];
    this.notify();
  }

  /** The kittens to draw for this pill at `now` (ms, the clock of the events): in order, without a leaving kitten whose time is up. */
  kittenView(id: string, now: number = performance.now()): Kitten[] {
    return kittenView(this.kittens[id] ?? [], now);
  }

  /** The approval a subagent asked for is over (answered, or timed out): its kitten stops waiting. Nothing for the parent's own approvals. */
  subagentApprovalOver(req: ApprovalInfo | null, t: number = performance.now()) {
    if (req?.agentId) this.kittenEvent("integration_claude", { type: "resolved", id: req.agentId, t });
  }

  /** The cat has fallen asleep (ten quiet minutes): a kitten whose stop never came, and whose own last event is that old, goes (every pill's list gets `sweep`). */
  sweepKittens(now: number = performance.now()) {
    for (const id of Object.keys(this.kittens)) {
      const next = kittenStep(this.kittens[id], { type: "sweep", t: now });
      if (next.length) this.kittens[id] = next;
      else delete this.kittens[id];
    }
    this.notify();
  }

  setFocus(id: string) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    this.focusId = id;
    t.pillBadge = null;
    this.notify();
  }

  updateTask(id: string, state: BotStateName) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.state = state;
    this.notify();
  }

  appendStep(id: string, step: string) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.steps.push(step);
    if (t.steps.length > 20) t.steps.shift();
    t.stepIndex = t.steps.length - 1;
    this.notify();
  }

  setPillBadge(id: string, badge: PillBadge | null) {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.pillBadge = badge;
    this.notify();
  }

  /** loadIntegrationTasks() — VS Code always on, the rest opt-in (max 4). */
  loadIntegrationTasks() {
    for (const proto of INTEGRATION_AGENTS) {
      const shouldLoad =
        proto.id === "integration_claude" || this.settings.activeIntegrations.includes(proto.id);
      const idx = this.tasks.findIndex((t) => t.id === proto.id);
      if (shouldLoad && idx < 0) this.tasks.push({ ...proto, steps: [] });
      if (!shouldLoad && idx >= 0) this.tasks.splice(idx, 1);
    }
    for (const sw of AGENT_SWITCHES) {
      const on = this.settings.activeIntegrations.includes(sw.id);
      const pill = this.tasks.find((t) => t.id === sw.id);
      if (on && !pill) {
        this.tasks.push({
          id: sw.id, name: agentPillName(sw.tag), color: agentColor(sw.tag),
          state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false,
        });
        this.giveCoats([sw.id]);
      } else if (!on && pill?.state === "idle") {
        // Switched off and nothing to do: the pill goes, as a transient one does. A busy one stays until its session's Stop or SessionEnd.
        this.removeTask(sw.id);
      }
    }
    // Order: integration_claude first, then agent_* pills (visible in slice(0,4)),
    // then other integrations in declaration order.
    const order = INTEGRATION_AGENTS.map((t) => t.id);
    this.tasks.sort((a, b) => {
      const isAgentA = a.id.startsWith("agent_");
      const isAgentB = b.id.startsWith("agent_");
      // integration_claude always first
      if (a.id === "integration_claude") return -1;
      if (b.id === "integration_claude") return 1;
      // agent_* before other integrations; preserve insertion order among themselves
      if (isAgentA && !isAgentB) return -1;
      if (isAgentB && !isAgentA) return 1;
      if (isAgentA && isAgentB) return 0;
      // both known integrations → declaration order
      return order.indexOf(a.id) - order.indexOf(b.id);
    });
    if (!this.focusId) this.focusId = "integration_claude";
    this.notify();
  }

  removeTask(id: string) {
    const sw = AGENT_SWITCHES.find((s) => s.id === id);
    if (sw && this.settings.activeIntegrations.includes(id)) {
      // A switched-on agent keeps its pill and goes idle (as the Mac's removeTask does for an active pill); its kittens and focus stay.
      const pill = this.tasks.find((t) => t.id === id);
      if (pill) {
        pill.state = "idle";
        pill.steps = [];
        pill.stepIndex = 0;
        pill.pillBadge = null;
        pill.name = agentPillName(sw.tag);
        this.notify();
      }
      return;
    }
    const idx = this.tasks.findIndex((t) => t.id === id);
    if (idx < 0) return;
    this.tasks.splice(idx, 1);
    delete this.kittens[id];
    if (this.focusId === id) this.focusId = this.tasks[0]?.id ?? "integration_claude";
    this.notify();
  }

  /** Creates a dynamic agent_ pill on first event; no-ops if it already exists.
   *  Inserted right after integration_claude so it appears in the visible slice(0,4). */
  upsertExternalAgent(id: string, name: string, color: string) {
    if (this.tasks.some((t) => t.id === id)) return;
    const at = this.tasks.findIndex((t) => t.id === "integration_claude") + 1;
    this.tasks.splice(at, 0, {
      id, name, color,
      state: "idle", stepIndex: 0, steps: [],
      source: "agent", isIntegration: false,
    });
    if (!this.focusId) this.focusId = id;
    this.giveCoats([id]);
    this.notify();
  }

  toggleIntegration(id: string) {
    // Only the services Settings lists and the agent switches can be toggled; any other id (Claude Code's own pill included) changes nothing.
    if (!TOGGLEABLE_INTEGRATION_IDS.includes(id) && !AGENT_SWITCHES.some((s) => s.id === id)) return;
    const active = this.settings.activeIntegrations;
    if (active.includes(id)) {
      this.settings.activeIntegrations = active.filter((x) => x !== id);
      if (this.focusId === id) this.focusId = "integration_claude";
    } else {
      if (active.length >= 4) return;
      this.settings.activeIntegrations = [...active, id];
    }
    this.loadIntegrationTasks();
  }

  defaultView(): IslandViewName {
    return this.tasks.length === 0 ? "empty" : "overview";
  }
}

export const State = new AppState();
