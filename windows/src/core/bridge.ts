// Thin wrapper over the Tauri commands/events. Every call is a no-op when the
// page is opened in a plain browser, so the island can be iterated on with
// `npm run dev` alone.

import { Channel, invoke, type InvokeArgs } from "@tauri-apps/api/core";
import { emitTo, listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { ClaudeChatLevel, ClaudeLevel, ClaudeStatus, ClaudeStep, Payer } from "./claude";
import type { AiAction, Settings } from "./state";
import type { ForegroundKind } from "./focusaware.ts";
import type { LiveProject } from "../projects/present.ts";
import type { DesktopWorld } from "../cat/desktopview";
import type { AddWord } from "../shelf/rules";
import type { ShelfEntry } from "../shelf/store";
import type { Conversation } from "../companion/core.ts";
import type { Head } from "../companion/store.ts";

export const IS_TAURI =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T | null> {
  const r = await callChecked<T>(cmd, args);
  return r.ok ? r.value : null;
}

/** What `callChecked` says: the command's value (null where there is no Tauri), or the command's refusal in its own fixed words. */
export type Checked<T> = { ok: true; value: T | null } | { ok: false; error: string };

/** The one place a command is invoked. A refusal is logged and given back as an answer; `call` turns it into null, so the island's calls behave as before. Outside Tauri it is `{ ok: true, value: null }`. */
async function callChecked<T>(cmd: string, args?: Record<string, unknown>): Promise<Checked<T>> {
  if (!IS_TAURI) return { ok: true, value: null };
  try {
    return { ok: true, value: (await invoke<T>(cmd, args)) ?? null };
  } catch (err) {
    console.error(`[notchmeow] ${cmd} failed`, err);
    return { ok: false, error: String(err) };
  }
}

/** Why the Settings file could not be used at boot: unreadable (the defaults are shown and nothing is written until the person chooses), or unparseable (kept
 * as `keptAs`, a file name only). */
export type SettingsProblem = { kind: "unreadable" } | { kind: "unparseable"; keptAs?: string };

export interface BootInfo {
  settings: Settings;
  /** Logical screen rect of the monitor the island lives on. */
  screen: { x: number; y: number; width: number; height: number; scale: number };
  version: string;
  hookPath: string;
  /** False where the OS has no global cursor (Wayland): see Island.followPageCursor. */
  cursorPoll: boolean;
  /** Whether the desktop cat's window can be put where we want it: false on GNOME, where Settings says so under the switch. */
  desktopPositioned: boolean;
  /** The user's home folder, for the Sidekick's reading of `~` in a path. */
  home: string;
  /** What the shelf can do here (sub-project G1): drag a file out of the island, send it through the system's share. */
  shelf: { dragOut: boolean; send: boolean };
  /** There is a Claude desktop app the Claude App pill can open (Windows); false on Linux, where Anthropic ships none. */
  claudeApp: boolean;
  /** How the frontmost app can be read here (focus awareness): "windows" or "x11" can name it, "none" cannot (Wayland, or no read at all). */
  foreground: ForegroundKind;
  /** Set when the settings file could not be used at start-up; null or absent when it could. */
  settingsProblem?: SettingsProblem | null;
}

export const Bridge = {
  boot: () => call<BootInfo>("boot"),

  /** Fire and forget: the island's saves. A refusal is logged by `call` and changes nothing in Rust. */
  saveSettings: (settings: Settings) => call<void>("save_settings", { settings }),
  /** The Settings window's save: true when the file was written, false when it was refused (the page then goes back to the stored value). */
  saveSettingsChecked: async (settings: Settings): Promise<boolean> => (await callChecked<void>("save_settings", { settings })).ok,
  /** Try again: the file is read once more. The settings it holds, or the refusal in its fixed sentence. */
  settingsRetryLoad: () => callChecked<Settings>("settings_retry_load"),
  /** Start fresh: the defaults are accepted and saves work again. Writes nothing itself. */
  settingsStartFresh: () => callChecked<void>("settings_start_fresh"),

  /** Shrink the window down to the invisible wake strip (hidden) or back to full. */
  setCollapsed: (collapsed: boolean) => call<void>("set_collapsed", { collapsed }),

  /**
   * Pushes the island shape in window coordinates. Rust flips click-through from
   * its own cursor poll, so the flag is never a frame behind a click.
   */
  setIslandRect: (x: number, y: number, width: number, height: number) =>
    call<void>("set_island_rect", { x, y, width, height }),

  /** The outside click: Rust reads the mouse buttons on every poll tick and sends `pointer-button` for each edge, only while this is on (the island is expanded). */
  watchPointerButtons: (on: boolean) => call<void>("watch_pointer_buttons", { on }),

  /** Give the window keyboard focus (chat field) and take it away again. */
  focusWindow: (focused: boolean) => call<void>("focus_window", { focused }),

  reposition: () => call<void>("reposition"),
  /** Corrects the webview's zoom when its pixel ratio is not the window's scale; true when it changed. */
  fitZoom: (dpr: number) => call<boolean>("fit_zoom", { dpr }),

  openUrl: (url: string) => call<void>("open_url", { url }),

  /** "Open terminal" → opens the folder in VS Code when `code` is on PATH. */
  openInVSCode: (path: string | null) => call<boolean>("open_in_vscode", { path }),

  /** The Claude App pill's Open: starts the Claude desktop app (Windows), or brings it forward. False where it cannot be found, and always on Linux. */
  openClaudeApp: () => call<boolean>("open_claude_app"),

  quit: () => call<void>("quit_app"),

  openSettingsWindow: (place?: string) => call<void>("open_settings_window", { place: place ?? null }),

  /** Writes to %LOCALAPPDATA%\NotchMeow\notchmeow.log, next to the Rust lines. */
  log: (message: string) => call<void>("log_line", { message }),

  // ── Claude Code hooks ─────────────────────────────────────────────────────
  hooksStatus: () => call<HookStatus>("hooks_status"),
  /** Diff to show before anything is written. `install: false` previews removal. */
  hooksPreview: (install: boolean) => callOrThrow<HookPreview>("hooks_preview", { install }),
  /**
   * Writes ~/.claude/settings.json — only ever after an explicit click, and only
   * when the file still matches the preview the user looked at.
   */
  hooksApply: (install: boolean, fingerprint: string) =>
    callOrThrow<string>("hooks_apply", { install, fingerprint }),

  // ── Gemini CLI and Antigravity hooks ──────────────────────────────────────
  // The same three steps for the agent's own config file (~/.gemini/…).
  agentHooksStatus: (agent: HookAgent) => call<HookStatus>("agent_hooks_status", { agent }),
  agentHooksPreview: (agent: HookAgent, install: boolean) =>
    callOrThrow<HookPreview>("agent_hooks_preview", { agent, install }),
  agentHooksApply: (agent: HookAgent, install: boolean, fingerprint: string) =>
    callOrThrow<string>("agent_hooks_apply", { agent, install, fingerprint }),

  approvalDecision: (requestId: string, decision: "allow" | "deny") =>
    call<void>("approval_decision", { requestId, decision }),
  /** "The card is up" — until this lands the relay only waits a moment. */
  approvalAck: (requestId: string) => call<void>("approval_ack", { requestId }),
  /** "Nobody can act on this" — Claude Code asks in the terminal right away. */
  approvalDecline: (requestId: string) => call<void>("approval_decline", { requestId }),
  /** The frontmost app's name, read once for one request (focus awareness); null when it cannot be read. */
  foregroundApp: () => call<string | null>("foreground_app"),

  // ── AI: chat, models, files, secrets ──────────────────────────────────────
  /**
   * One chat turn, streamed back event by event. Keys and file bytes never
   * leave Rust; `attachments` are inbox paths from `ingestFile`. `quick` marks an Explain turn: Rust plans no tools and holds the chat there.
   */
  aiChat: (
    feature: Feature,
    text: string,
    attachments: string[],
    regenerate: boolean,
    system: string,
    quick: boolean,
    onEvent: (event: AiEvent) => void,
  ) => {
    if (!IS_TAURI) throw new Error("not running inside NotchMeow");
    const channel = new Channel<AiEvent>();
    channel.onmessage = onEvent;
    return callOrThrow<void>("ai_chat", { feature, text, attachments, regenerate, system, quick, onEvent: channel });
  },
  /**
   * A quick action (Fix, Rewrite): one model turn with its own system text and its own history, streamed back like a chat turn. The chat's conversation is
   * never touched. `attachments` are inbox paths, as for `aiChat`.
   */
  aiQuick: (feature: Feature, system: string, text: string, attachments: string[], onEvent: (event: AiEvent) => void) => {
    if (!IS_TAURI) throw new Error("not running inside NotchMeow");
    const channel = new Channel<AiEvent>();
    channel.onmessage = onEvent;
    return callOrThrow<void>("ai_quick", { feature, system, text, attachments, onEvent: channel });
  },
  /** Opens a saved conversation in the chat: its words become the history, and a Claude plan session is told them on its first turn. */
  aiLoadTurns: (turns: { role: "user" | "assistant"; text: string }[]) => call<void>("ai_load_turns", { turns }),
  /** What the companion last sent a model, one line per message part (memory only: a file is named, never shown). */
  companionLastSent: async (): Promise<string[]> => (await call<string[]>("companion_last_sent")) ?? [],
  /** Stop: cancels the reply on its way. */
  aiCancel: () => call<void>("ai_cancel"),
  /** Checks this computer (and the server the user added) for model servers. */
  aiDiscover: () => call<AiServer[]>("ai_discover"),
  /** A provider's live models. For a cloud provider it is also the key check. */
  aiListModels: (provider: string) => callOrThrow<ModelInfo[]>("ai_list_models", { provider }),
  /** What Auto or the chosen model resolves to right now. No network call. */
  aiResolve: (feature: Feature) => call<Resolution>("ai_resolve", { feature }),
  /** Loads the selected local model before the first message. */
  aiPrewarm: (feature: Feature) => call<void>("ai_prewarm", { feature }),
  // ── Claude Code (the user's own installed program) ───────────────────────
  /** Where it is, its version and whether it is signed in. Looked at when Settings opens and before a chat's first turn. */
  claudeStatus: () => call<ClaudeStatus>("claude_status"),
  /** What Claude may do in this chat. Read-only and Agent need a folder that exists. */
  claudeSetLevel: (level: ClaudeLevel, folder: string | null) => callOrThrow<ClaudeChatLevel>("claude_set_level", { level, folder }),
  /** The system's folder dialog; null when cancelled or when this system has none. */
  claudePickFolder: () => call<string>("claude_pick_folder"),
  /** Opens a terminal that runs `claude auth login`; the sign-in finishes in the browser. */
  claudeSignIn: () => call<boolean>("claude_sign_in"),
  /** Starts a new conversation (a file was dropped, or the chat was cleared). */
  chatReset: () => call<void>("chat_reset"),
  /** Copies a dropped file into the inbox. */
  ingestFile: (path: string) => callOrThrow<DroppedFile>("ingest_file", { path }),
  /** Copies a pasted screenshot into the inbox: the PNG's bytes are the raw body of the invoke (never base64). Rust refuses anything else. */
  ingestPng: (bytes: Uint8Array) => callOrThrow<DroppedFile>("ingest_png", bytes),
  /** The drag-out spike (Debug builds of the app): drags a small test file of Rust's own out of the island. Resolves when the drag ends: "copied", "none" or "cancelled". */
  dragOutSpike: () => callOrThrow<string>("drag_out_spike"),
  // ── The shelf (sub-project G1): the page holds ids, Rust holds the paths ──────
  /** The shelf as it opens, each item with whether its original is gone. */
  shelfList: () => callOrThrow<ShelfEntry[]>("shelf_list"),
  /** The files of a drop on the Shelf half: the new list and one word per path. */
  shelfAdd: (paths: string[]) => callOrThrow<{ entries: ShelfEntry[]; results: AddWord[] }>("shelf_add", { paths }),
  shelfRemove: (id: string) => callOrThrow<ShelfEntry[]>("shelf_remove", { id }),
  shelfClear: () => callOrThrow<ShelfEntry[]>("shelf_clear"),
  /** Drag these shelf items out of the island (the pointer is down). Resolves when the drag ends: "copied", "none" or "cancelled". */
  shelfDragOut: (ids: string[]) => callOrThrow<string>("shelf_drag_out", { ids }),
  /** Show in Explorer or the file manager, with the file selected. */
  shelfReveal: (id: string) => callOrThrow<void>("shelf_reveal", { id }),
  /** The system's Share window over the island (Windows only: `BootInfo.shelf.send`). Resolves when the window has been asked for. */
  shelfSend: (ids: string[]) => callOrThrow<void>("shelf_send", { ids }),
  /** Ask: Rust copies the shelf item into the inbox like a drop on Ask, and the chat starts with it. */
  shelfAsk: (id: string) => callOrThrow<DroppedFile>("shelf_ask", { id }),
  /** Only ever tells you whether a key exists — never its value. */
  secretPresent: (key: string) => call<boolean>("secret_present", { key }),
  /** The Settings window's three-way answer: a store that cannot be read is "unreadable", never absent. null when the call itself failed. */
  secretPresence: (key: string) => call<"present" | "absent" | "unreadable">("secret_presence", { key }),
  secretSet: (key: string, value: string) => callOrThrow<void>("secret_set", { key, value }),
  secretClear: (key: string) => callOrThrow<void>("secret_clear", { key }),

  // ── Integrations ──────────────────────────────────────────────────────────
  refreshIntegration: (id: string) => call<void>("refresh_integration", { id }),
  /** Opens the configured n8n instance in the browser. */
  openN8n: () => call<void>("open_n8n"),

  /** Tray → Pause. Stops the integration pollers, not just the island. */
  setPaused: (paused: boolean) => call<void>("set_paused", { paused }),

  // ── The desktop cat (sub-project H): its own window, which the island's page runs and the desktop page draws ──
  /** The connected screens, the island's screen and whether the window can be put where we want it, in the points the contract's rules use. */
  desktopScreens: () => call<DesktopWorld>("desktop_screens"),
  /** The window is `w` x `h` CSS px with the head's centre at (headX, headY); `shapes` are the circles that take the mouse, in window px. */
  desktopLayout: (w: number, h: number, headX: number, headY: number, shapes: { x: number; y: number; r: number }[]) => call<void>("desktop_layout", { w, h, headX, headY, shapes }),
  /** Puts the window where the head's centre is at this spot (points). */
  desktopPlace: (x: number, y: number) => call<void>("desktop_place", { x, y }),
  desktopShow: (visible: boolean) => call<void>("desktop_show", { visible }),
  /** While the desktop cat is carried by the pointer the whole window takes the mouse. */
  desktopDrag: (on: boolean) => call<void>("desktop_drag", { on }),
  /** Where the system moves windows by itself (GNOME): the system drags the window. */
  desktopNativeDrag: () => call<void>("desktop_native_drag"),
  /** The cursor in points, or null where the system gives an app none (Wayland). */
  desktopCursor: () => call<{ x: number; y: number } | null>("desktop_cursor"),
  /** The cat is awake and drawn (shown, not asleep, not away): only then does Rust run its light checks (the screens and a fullscreen app, 2 Hz). */
  desktopAwake: (on: boolean) => call<void>("desktop_awake", { on }),
  /** The system's double-click time in ms, or null where the app cannot read it (the page then waits 500 ms). */
  desktopDoubleClick: () => call<number>("desktop_double_click_ms"),
  /** The chat's own window (the pop-out): shown on the conversation `conversationId` (null: a new chat), hidden again, and the relay between its page and the island's. */
  showChatWindow: async (conversationId: string | null): Promise<boolean> => IS_TAURI && (await callChecked<void>("show_chat_window", { conversationId })).ok,
  hideChatWindow: () => call<void>("hide_chat_window"),
  chatRelay: (to: "island" | "chat", msg: unknown) => call<void>("chat_relay", { to, msg }),
  /** A message between the island's page (the brain) and the desktop page (the body): `to` is the window's label. */
  desktopRelay: (to: "island" | "desktop", msg: unknown) => call<void>("desktop_relay", { to, msg }),
  /** The tray item reads "Bring the cat home" while the cat is out. */
  desktopMenuText: (out: boolean) => call<void>("desktop_menu_text", { out }),
  /** The tray item reads "Projects" or "Projects (N)" (tray.rs projects_text). */
  projectsMenuText: (count: number) => call<void>("projects_menu_text", { count }),
  /** The island's live projects, folder names and names only, to the Settings window (Project cats). Nothing outside Tauri. */
  emitProjectsLive: async (list: readonly LiveProject[]): Promise<void> => {
    if (IS_TAURI) await emitTo("settings", "projects-live", list).catch((err: unknown) => console.error("[notchmeow] projects-live failed", err));
  },
  /** The Settings window asks the island for its live projects (the island answers with emitProjectsLive). Nothing outside Tauri. */
  askProjectsLive: async (): Promise<void> => {
    if (IS_TAURI) await emitTo("island", "projects-live-ask").catch((err: unknown) => console.error("[notchmeow] projects-live-ask failed", err));
  },

  // ── The Sidekick (sub-project F1) ──
  /** One short question to a model on this computer (never a network or cloud one), answered with one line, or null: the Sidekick's nicer wording. Nothing is stored or logged. */
  aiOneshot: (system: string, prompt: string) => call<string>("ai_oneshot", { system, prompt }),
  /** The name of the local model that wording would come from, or null when there is none. */
  aiLocalModel: () => call<string>("ai_local_model"),
  /** Fills the clipboard with a text (the paths of the files dropped on an agent's cat). True when it is there. Nothing is pasted anywhere. */
  copyText: (text: string) => call<boolean>("copy_text", { text }),
  /** Seconds since the user's last keyboard or mouse input, or null where the system does not say. Asked when a hook event comes, when the island opens and on an unlock. */
  sidekickIdleSeconds: () => call<number>("sidekick_idle_seconds"),

  // ── The companion's conversation files (F3a-tauri): Rust holds them. Outside Tauri there are none. ──
  /** The saved conversations' heads (`[]` outside Tauri, or when the folder cannot be read). */
  companionList: async (): Promise<Head[]> => (await call<Head[]>("companion_list")) ?? [],
  /** One conversation as it was saved, or null: absent, a link, over the size, or not a record. */
  companionLoad: (id: string) => call<unknown>("companion_load", { id }),
  /** true when the file was written; false when it was refused (Rust logs a fixed sentence, and nothing of the record). */
  companionSave: async (record: Conversation): Promise<boolean> => IS_TAURI && (await callChecked<void>("companion_save", { record })).ok,
  /** true when the conversation is gone (a file that was not there counts). */
  companionDelete: async (id: string): Promise<boolean> => IS_TAURI && (await callChecked<void>("companion_delete", { id })).ok,
  /** true when every conversation file was removed; false outside Tauri, or when one could not be. */
  companionDeleteAll: async (): Promise<boolean> => IS_TAURI && (await callChecked<void>("companion_delete_all")).ok,
};

export interface IntegrationUpdate {
  id: string;
  data: Record<string, unknown>;
  error: string | null;
  event: { success: boolean; label: string; detail: string | null } | null;
}

export type Feature = "chat" | "files";
export type Placement = "local" | "network" | "cloud";

/** The contract's 12 error kinds (docs/AI-PROVIDERS.md): a provider or the network failed. */
export type ErrorKind =
  | "offline" | "unreachable" | "timeout" | "server" | "rate_limited" | "overloaded"
  | "auth" | "bad_request" | "billing" | "refusal" | "cancelled" | "interrupted";

/**
 * The island's own notices (session::ProblemKind in Rust). NOT contract error kinds: they
 * never come from a provider, and arrive as `problem` events, never as `error` events.
 */
export type ProblemKind =
  | "cant_see" | "scanned_pdf" | "heic" | "rejected" | "unreadable" | "missing_model" | "outdated" | "empty_reply";

/** What `ai_chat` streams — mirrors session::AiEvent in Rust. */
export type AiEvent =
  | { type: "started"; provider: string; model: string; placement: Placement; caption: string; fallback: boolean; waking: string | null }
  | { type: "delta"; text: string }
  | { type: "citation"; url: string; title: string }
  | { type: "notice"; text: string }
  | { type: "done"; text: string; interrupted: boolean; cancelled: boolean }
  | { type: "error"; kind: ErrorKind; message: string; action: AiAction | null; retryAfter: number | null; resetsAt?: number }
  | { type: "problem"; kind: ProblemKind; message: string; action: AiAction | null }
  | { type: "emptyState" }
  /** Claude Code: the session this run belongs to, so its hook events are the chat's. `retired` is the id this turn gave up. */
  | { type: "claudeSession"; sessionId: string; retired: string | null }
  | ({ type: "step" } & ClaudeStep)
  | { type: "engine"; sessionId: string; model: string; paidBy: Payer; version: string | null };

export interface ModelInfo {
  id: string;
  displayName: string;
  contextTokens: number | null;
  capabilities: { tools: boolean; vision: boolean; json: boolean };
}

export interface AiServer {
  provider: string;
  name: string;
  baseUrl: string;
  host: string;
  placement: Placement;
  status: "running" | "off" | "notInstalled" | "outdated";
  models: ModelInfo[];
  /** Plain http to another computer. */
  unencrypted: boolean;
}

export interface Resolution {
  empty: boolean;
  auto: boolean;
  provider: string | null;
  model: string | null;
  placement: Placement | null;
  modelName: string | null;
  /** The drop card: "Claude", "Local · qwen3.5:2b". */
  reader: string | null;
  /** Auto's local retry: "Local · qwen3.5:2b". */
  fallback: string | null;
}

export interface DroppedFile {
  name: string;
  path: string;
  size: number;
}

export interface HookStatus {
  installed: boolean;
  settingsPath: string;
  hookPath: string;
  hookReady: boolean;
  /** Set when settings.json is there but cannot be used (a fixed sentence): the card says so instead of "Not installed". Absent on the agents' files. */
  error?: string | null;
  /** Why, when `error` is set: `unreadable`, `not valid JSON`, `not an object` or `unexpected hooks shape` (fixed words, never the file's text or its path). */
  reason?: string | null;
}

/** The agents whose hooks live in a config file of their own; also their `--agent` / `nm_agent`. */
export type HookAgent = "gemini" | "antigravity";

export interface HookPreview {
  diff: string;
  /** The dated backup's path; empty when there is no file yet, so nothing is backed up. */
  backup: string;
  settingsPath: string;
  /** Hand back to hooksApply so only the reviewed diff is ever written. */
  fingerprint: string;
}

/** Same as `call`, but surfaces the error so the UI can show what went wrong. */
async function callOrThrow<T>(cmd: string, args?: InvokeArgs): Promise<T> {
  if (!IS_TAURI) throw new Error("not running inside NotchMeow");
  return invoke<T>(cmd, args);
}

export type BridgeEvent =
  | { name: "cursor"; payload: { x: number; y: number; down?: boolean } }
  | { name: "pointer-button"; payload: { down: boolean; x: number; y: number; own: boolean } }
  | { name: "tray"; payload: string }
  | { name: "desktop-msg"; payload: unknown }
  | { name: "sidekick-away"; payload: { signal: string } }
  | { name: "hook"; payload: Record<string, unknown> }
  | { name: "screen-changed"; payload: null };

export interface DragDropPayload {
  type: "enter" | "over" | "drop" | "leave";
  paths?: string[];
  /** Where the pointer is, in physical pixels of the webview (Tauri sends it with enter, over and drop). The half of the drop view is decided from it where the OS has no global cursor. */
  position?: { x: number; y: number };
}

/** Files dragged onto the island. Only reaches us when the window takes the mouse. */
export async function onDragDrop(handler: (e: DragDropPayload) => void) {
  if (!IS_TAURI) return () => {};
  return getCurrentWebview().onDragDropEvent((event) => {
    handler(event.payload as DragDropPayload);
  });
}

export async function onEvent<T>(name: string, handler: (payload: T) => void) {
  if (!IS_TAURI) return () => {};
  return listen<T>(name, (e) => handler(e.payload));
}

/** The three cloud providers, in the canonical order (Claude, OpenAI, Google): the one table the chat picker and Settings share. */
export const CLOUD_PROVIDERS = [
  { id: "anthropic", brand: "Claude", key: "anthropic-api-key", placeholder: "sk-ant-..." },
  { id: "openai", brand: "OpenAI", key: "openai-api-key", placeholder: "sk-..." },
  { id: "google", brand: "Google", key: "google-api-key", placeholder: "AIza..." },
] as const;
