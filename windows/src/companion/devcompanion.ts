// The Companion's dev samples (sub-project F3a-tauri, Task 11): the chat on made-up words, with stand-ins for what it reaches (the saved conversations in memory, the
// model's answer, the chat's Rust backend), so a sample writes no file, runs no model and reads nothing of this computer. Two routes use it, both in the dev server only:
// `chat.html?sample=1&scene=<scene>` (what render-companion.sh cuts its pictures from) and the `?dev` page's "Companion" panel (the same scenes, plus the Prompt box that
// shows the text the companion would send). Only the dev server loads this file: chatwin/main.ts and cat/dev.ts check import.meta.env.DEV.

import { State, type ChatMessage } from "../core/state.ts";
import { IS_TAURI, type Feature, type Resolution } from "../core/bridge.ts";
import type { ClaudeChatLevel } from "../core/claude.ts";
import { chatPromptHeight } from "../core/layout.ts";
import { ProjectsModel } from "../projects/model.ts";
import { THEME } from "../theme.generated.ts";
import { buildChat, type ChatDeps } from "../views/chat.ts";
import type { ChatLink } from "./link.ts";
import { MENU } from "./chrome.ts";
import { cloudNotice, type Conversation } from "./core.ts";
import type { QuickResult } from "./quick.ts";
import type { ChatBackend } from "./session.ts";
import type { Head, StoreBackend } from "./store.ts";
import { contextOf, localDay, systemFor, type TurnContext } from "./turn.ts";

export const SCENES = [
  "chat-0", "chat-4", "chat-8", "chat-14", "conversations", "quick-running", "quick-done", "screenshot-chip", "folder-read", "folder-agent", "cloud-line",
] as const;
export type Scene = (typeof SCENES)[number];

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;

const LOCAL_CAPTION = "local · qwen3.5:2b";
const CLOUD_CAPTION = "cloud · Claude Sonnet 5.5";
const SHOT = { name: "shot.png", path: "C:\\dev\\inbox\\shot.png" };
const NOW = Date.now();
const HOUR = 3_600_000;

const MARKDOWN_REPLY =
  "Here is a **short plan** for the week:\n\n- Read the `notes.md` file in `C:\\dev\\notchmeow`\n- Open the [sample guide](https://example.com/sample-guide)\n- Write one line per task\n\nTell me which task you want first.";

/** Made-up question and answer pairs; the second answer is the Markdown reply (a list, bold, code and a link). */
const PAIRS: readonly (readonly [string, string])[] = [
  ["Can you help me plan the week?", "Yes. Let's start with the three tasks that block the rest."],
  ["What should I read first?", MARKDOWN_REPLY],
  ["Thanks. What about the notes?", "Keep one dated line per note."],
  ["Where do the files go?", "Put them in the project folder, next to the notes."],
  ["Is there anything else?", "Check the list again at the end of the day."],
  ["Good. And the reading list?", "Pick two short articles for Monday."],
  ["Last one, the garden?", "Water the beds before the weekend."],
];

const LOCAL: Resolution = { empty: false, auto: false, provider: "ollama", model: "qwen3.5:2b", placement: "local", modelName: "qwen3.5:2b", reader: null, fallback: null };
const CLOUD: Resolution = { empty: false, auto: false, provider: "anthropic", model: "claude-sonnet-5-5", placement: "cloud", modelName: "Claude Sonnet 5.5", reader: null, fallback: null };
const PLAN: Resolution = { empty: false, auto: false, provider: "claudeCode", model: "sonnet", placement: "cloud", modelName: null, reader: null, fallback: null };

let nextId = 5000;

/** The first `pairs` question and answer pairs as chat messages; each answer carries the local caption. */
function turns(pairs: number): ChatMessage[] {
  const out: ChatMessage[] = [];
  for (const [question, answer] of PAIRS.slice(0, pairs)) {
    out.push({ id: ++nextId, role: "user", content: question });
    out.push({ id: ++nextId, role: "assistant", content: answer, caption: LOCAL_CAPTION });
  }
  return out;
}

/** A cloud brain's chat: the one-time cloud line sits between the question and the answer, as a send shows it. */
function cloudHistory(): ChatMessage[] {
  return [
    { id: ++nextId, role: "user", content: "Summarize my notes, please." },
    { id: ++nextId, role: "note", content: cloudNotice("Anthropic"), action: null },
    { id: ++nextId, role: "assistant", content: "Your notes cover three tasks and one date.", caption: CLOUD_CAPTION },
  ];
}

interface SceneSpec {
  history: () => ChatMessage[];
  resolution: Resolution;
  level?: ClaudeChatLevel;
  quick?: QuickResult;
  file?: boolean;
  conversations?: boolean;
}

const SPECS: Record<Scene, SceneSpec> = {
  "chat-0": { history: () => turns(0), resolution: LOCAL },
  "chat-4": { history: () => turns(2), resolution: LOCAL },
  "chat-8": { history: () => turns(4), resolution: LOCAL },
  "chat-14": { history: () => turns(7), resolution: LOCAL },
  conversations: { history: () => turns(2), resolution: LOCAL, conversations: true },
  "quick-running": {
    history: () => turns(1), resolution: LOCAL,
    quick: { kind: "fix", text: "The week has three tasks. Start with the blocked one, then", running: true, cut: false, note: null },
  },
  "quick-done": {
    history: () => turns(1), resolution: LOCAL,
    quick: { kind: "rewrite", text: "Plan the week in three tasks, and start with the one that blocks the rest.", running: false, cut: false, note: null },
  },
  "screenshot-chip": { history: () => turns(1), resolution: LOCAL, file: true },
  "folder-read": { history: () => turns(1), resolution: PLAN, level: { level: "read", folder: "C:\\dev\\notchmeow" } },
  "folder-agent": { history: () => turns(1), resolution: PLAN, level: { level: "agent", folder: "C:\\dev\\notchmeow" } },
  "cloud-line": { history: cloudHistory, resolution: CLOUD },
};

/** Six saved conversations, two pinned. Made-up titles and words; held in memory only. */
function sampleRecords(): Conversation[] {
  const titles: [string, string, boolean][] = [
    ["sample-plan", "Plan the week", true],
    ["sample-notes", "Notes for the release", true],
    ["sample-trip", "Trip list", false],
    ["sample-recipe", "Dinner ideas", false],
    ["sample-reading", "Reading list", false],
    ["sample-garden", "Garden plan", false],
  ];
  return titles.map(([id, title, pinned], i): Conversation => {
    const at = NOW - (i + 1) * HOUR;
    return {
      version: 1, id, title, pinned, createdAt: at, updatedAt: at,
      messages: [
        { role: "user", text: `A made-up question about ${title.toLowerCase()}.`, caption: "", files: [] },
        { role: "assistant", text: "A made-up answer.", caption: LOCAL_CAPTION, files: [] },
      ],
    };
  });
}

/** The saved conversations in memory: the sample's own store, so the Conversations pane never reads or writes the real files. */
function sampleStore(): StoreBackend {
  const map = new Map<string, Conversation>(sampleRecords().map((r) => [r.id, r]));
  return {
    async list(): Promise<Head[]> {
      return [...map.values()].map(({ id, title, pinned, updatedAt }) => ({ id, title, pinned, updatedAt }));
    },
    async load(id: string) {
      return map.get(id) ?? null;
    },
    async save(rec: Conversation) {
      map.set(rec.id, rec);
      return true;
    },
    async remove(id: string) {
      return map.delete(id);
    },
    async removeAll() {
      map.clear();
      return true;
    },
  };
}

// The Projects view the Prompt box reads: one made-up session in a made-up folder, in a model of its own (never State.projects).
let sampleModel: ProjectsModel | null = null;
function sampleView() {
  if (sampleModel === null) {
    sampleModel = new ProjectsModel({ home: "C:/dev/home" });
    sampleModel.hook({ hook_event_name: "UserPromptSubmit", session_id: "dev-companion", cwd: "C:/dev/Code/notchmeow", prompt: "dev prompt" });
  }
  return sampleModel.view();
}

const sampleLink: ChatLink = {
  context: (): TurnContext => contextOf({ view: sampleView(), attention: false, mood: "idle" }),
  approval: () => null,
  decide: () => undefined,
  release: () => undefined,
  session: () => undefined,
  forget: () => undefined,
};

const sampleChat: ChatBackend = { reset: () => undefined, loadTurns: () => undefined };
const sampleActions = { openSettingsWindow: () => undefined, openUrl: () => undefined, emote: () => undefined };

/** The model the field shows. Set by the scene; the chat reads it through deps.resolve. */
let shown: Resolution = LOCAL;

function depsFor(store: StoreBackend): ChatDeps {
  return { store, chat: sampleChat, resolve: async (_feature: Feature) => shown };
}

function isScene(name: string): name is Scene {
  return (SCENES as readonly string[]).includes(name);
}

/** Puts the chat's state into a scene's. The chat's own view (its menu, its pane) is driven by its buttons in `openScene`. */
function applyScene(scene: Scene): void {
  const s = SPECS[scene];
  shown = s.resolution;
  State.chatHistory = s.history();
  State.localAnswers = [];
  State.chatId = null;
  State.chatTitle = null;
  State.chatPinned = false;
  State.chatPoppedOut = false;
  State.quickResult = s.quick ?? null;
  State.claudeLevel = s.level ?? { level: "chat", folder: null };
  State.droppedFile = s.file ? { ...SHOT } : null;
  State.pendingAttachment = s.file ? SHOT.path : null;
  State.notify();
}

function clickFirst(root: HTMLElement, selector: string, text?: string): void {
  const hit = Array.from(root.querySelectorAll<HTMLElement>(selector)).find((el) => text === undefined || el.textContent === text);
  hit?.click();
}

/** The Conversations pane is reached the way a person reaches it: the ⋯ chip, then the menu's Conversations line. */
function openScene(root: HTMLElement, scene: Scene): void {
  if (!SPECS[scene].conversations) return;
  clickFirst(root, 'button[title="Conversations and new chat"]');
  clickFirst(root, "button.picker-item", MENU.conversations);
}

/** The line the app window shows where a sample would run. */
export const IN_APP_NOTE = "The chat samples run in a browser, not in the app window.";

function inAppNote(): HTMLElement {
  const note = document.createElement("p");
  note.className = "chat-note";
  note.textContent = IN_APP_NOTE;
  return note;
}

/** The `?dev` panel inside the app window: the Prompt box only, built from the sample view and the settings, with no chat, no Bridge call and no change to State. */
function mountPromptOnly(root: HTMLElement, before: Node | null): void {
  const box = document.createElement("section");
  box.id = "companion-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  const title = document.createElement("h2");
  title.style.cssText = "font-size:17px;font-weight:600;margin:0 0 2px";
  title.textContent = "Companion (chat samples)";
  const line = document.createElement("p");
  line.style.cssText = `color:${B.dim};margin:0 0 12px;font-size:13px`;
  line.textContent = IN_APP_NOTE;
  const prompt = document.createElement("pre");
  prompt.id = "companion-dev-prompt";
  prompt.style.cssText = `color:${B.dim};font-size:12px;margin:0;white-space:pre-wrap`;
  const text = systemFor(contextOf({ view: sampleView(), attention: false, mood: "idle" }), State.settings, localDay(new Date()));
  prompt.textContent = `Prompt (systemFor, device pc):\n${text}`;
  box.append(title, line, prompt);
  root.insertBefore(box, before);
}

/** The chat window's picture route: `chat.html?sample=1&scene=<scene>` mounts the chat on one scene, into the host. Unknown scene names show chat-4. */
export function mountChatSample(host: HTMLElement, name: string): void {
  // In the app's own webview the samples never run: they would drive the real Bridge and overwrite the live State. The app window says so and stops.
  if (IS_TAURI) {
    host.append(inAppNote());
    return;
  }
  const scene: Scene = isScene(name) ? name : "chat-4";
  applyScene(scene);
  const chat = buildChat(sampleActions, () => undefined, sampleLink, depsFor(sampleStore()));
  host.append(chat.el);
  chat.el.classList.add("on");
  State.subscribe(() => chat.sync());
  chat.sync();
  void chat.refreshModel().then(() => openScene(chat.el, scene));
}

/** The `?dev` page's "Companion" panel: the chat in a frame, one button per scene, the quiet and session switches, and the Prompt box (what systemFor builds). */
export function mountCompanionDev(root: HTMLElement, before: Node | null): void {
  if (IS_TAURI) {
    mountPromptOnly(root, before);
    return;
  }
  const chat = buildChat(sampleActions, () => undefined, sampleLink, depsFor(sampleStore()));
  let quietOn = false;
  let sessionsOn = true;

  const box = document.createElement("section");
  box.id = "companion-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  const title = document.createElement("h2");
  title.style.cssText = "font-size:17px;font-weight:600;margin:0 0 2px";
  title.textContent = "Companion (chat samples)";
  const intro = document.createElement("p");
  intro.style.cssText = `color:${B.dim};margin:0 0 12px;font-size:13px`;
  intro.textContent = "The chat on made-up words, in a frame the width of the island's chat. Each button sets one scene. Every stand-in is in memory: no file is written, no model runs and nothing is read from this computer.";
  box.append(title, intro);

  const frame = document.createElement("div");
  frame.style.cssText = "width:640px;max-width:100%;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 12px";
  chat.el.classList.add("on");
  frame.append(chat.el);
  box.append(frame);

  const row = (label: string, ...buttons: HTMLButtonElement[]) => {
    const r = document.createElement("div");
    r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center;font-size:12px";
    const text = document.createElement("span");
    text.textContent = label;
    r.append(text, ...buttons);
    box.append(r);
  };
  const button = (label: string, onclick: () => void): HTMLButtonElement => {
    const b = document.createElement("button");
    b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
    return b;
  };
  const prompt = document.createElement("pre");
  prompt.id = "companion-dev-prompt";
  prompt.style.cssText = `color:${B.dim};font-size:12px;margin:0;white-space:pre-wrap`;

  const paint = () => {
    frame.style.height = `${chatPromptHeight(State.chatHistory.length)}px`;
    const ctx = contextOf({ view: sampleView(), attention: quietOn, mood: "idle" });
    const settings = { ...State.settings, companion: { ...State.settings.companion, seeSessions: sessionsOn } };
    prompt.textContent = `Prompt (systemFor, device pc):\n${systemFor(ctx, settings, localDay(new Date()))}`;
  };

  const sceneLabels: Record<Scene, string> = {
    "chat-0": "0 messages", "chat-4": "4 messages", "chat-8": "8 messages", "chat-14": "14 messages",
    conversations: "Conversations", "quick-running": "Fix running", "quick-done": "Fix done", "screenshot-chip": "Screenshot chip",
    "folder-read": "Folder: read", "folder-agent": "Folder: agent", "cloud-line": "Cloud line",
  };
  const sceneButtons = SCENES.map((scene) => button(sceneLabels[scene], () => {
    applyScene(scene);
    void chat.refreshModel().then(() => openScene(chat.el, scene));
  }));
  row("Scene:", ...sceneButtons);
  const quietButton = button("Quiet: off", () => {
    quietOn = !quietOn;
    quietButton.textContent = `Quiet: ${quietOn ? "on" : "off"}`;
    paint();
  });
  const sessionsButton = button("See my sessions: on", () => {
    sessionsOn = !sessionsOn;
    sessionsButton.textContent = `See my sessions: ${sessionsOn ? "on" : "off"}`;
    paint();
  });
  row("Companion:", quietButton, sessionsButton);
  box.append(prompt);

  State.subscribe(() => {
    chat.sync();
    paint();
  });
  paint();
  chat.sync();
  root.insertBefore(box, before);
}
