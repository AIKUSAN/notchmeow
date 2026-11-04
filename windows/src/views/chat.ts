// Chat view — DOM port of PromptView / ChatBubble / TypingDotsView from
// IslandViewContent.swift, plus the AI layer's parts: the model chip, streamed
// replies with their caption and sources, notes with one action, and the empty
// state. Every model call goes through Rust (`Bridge.aiChat`).

import { h, svg, clear } from "./dom";
import { ICONS } from "./icons";
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiEvent, type AiServer, type Feature, type Resolution } from "../core/bridge";
import { GIT_FOR_WINDOWS, INSTALL_GUIDE, endUnfinished, planLimitNote, stepRow, type ClaudeLevel } from "../core/claude.ts";
import { featureFor, forgetDrop, stillBusy } from "../core/feature";
import { Sound } from "../core/sound";
import { State, type AiAction, type ChatMessage, type ModelChoice } from "../core/state";
import { cloudLine, localDay, systemFor } from "../companion/turn.ts";
import type { ChatLink } from "../companion/link.ts";
import { conversationsKeep, quickRequest, quickResultClean } from "../companion/core.ts";
import { isImageName, keepWaiting, quickNote, type QuickResult } from "../companion/quick.ts";
import { bridgeStore, type StoreBackend } from "../companion/store.ts";
import type { Head } from "../companion/store.ts";
import { bridgeChat, type ChatBackend, nextMessageId, openConversation, removeAll, removeOne, rename, saveCurrent, startNewChat, togglePin } from "../companion/session.ts";
import { BRING_BACK, CUT_NOTE, FOLDER_ROWS, FOLDER_TITLE, LIST_NOTES, MENU, OPEN_FAILED_NOTE, PANE, POPPED_OUT_NOTE, NO_MODEL_NOTE, QUICK_CLOSE, QUICK_COPY, QUICK_TITLES, QUICK_TOO_LONG, SCREENSHOT_CHIP, STATUS_IN_ISLAND_NOTE, UNSAVED_NOTE, chipLabel, folderLabel } from "../companion/chrome.ts";
import { parseMarkdown, renderBlocks } from "../companion/markdown.ts";
import { Hub } from "../sidekick/hub.ts";
import { matchStatusQuestion } from "../sidekick/core.ts";
import { STATUS_CAPTION, STATUS_CHIP_TEXT, answerStatus, interleave, type LocalAnswer } from "../sidekick/statuschat.ts";
import type { ViewActions, ViewHost } from "./views";

/** What the chat needs of the views' actions: the Settings window, a link, and a one-off cat face. `collapse` is the island's alone: only a chat with it offers Pop out. */
export type ChatActions = Pick<ViewActions, "openSettingsWindow" | "openUrl" | "emote"> & Partial<Pick<ViewActions, "collapse">>;

/** How many times a busy cloud is retried on its own before the note just waits. */
const MAX_AUTO_RETRIES = 3;
/** A local model that hasn't said a word by now is probably loading. */
const WAKING_AFTER_MS = 1500;
/** A quick action's Claude Code session is kept as the chat's this long after its turn ends, so a late Stop hook still routes to the chat. */
const QUICK_SESSION_GRACE_MS = 3000;

const GUIDE_LINKS: [string, string][] = [
  ["Ollama", "https://ollama.com/download"],
  ["LM Studio", "https://lmstudio.ai"],
];

/** What the next message will carry: the file dropped on it, if one is waiting. */
function pendingAttachments(): string[] {
  return State.pendingAttachment ? [State.pendingAttachment] : [];
}

/**
 * The setting the next message will use, for the model chip, the picker and pre-warming: File
 * questions while a dropped file is waiting to go with it and for the rest of a conversation that
 * holds a file, Chat otherwise. The conversation's messages decide, never `State.droppedFile`,
 * which is never cleared.
 */
function nextFeature(): Feature {
  return featureFor(pendingAttachments(), State.chatHistory);
}

function typingDots(): HTMLElement {
  return h(
    "div",
    { class: "chat-row" },
    h("div", { class: "typing" }, h("i"), h("i"), h("i")),
  );
}

/** The coloured chip showing what the question is about (a dropped file). */
function contextChip(label: string): HTMLElement {
  const chip = h("div", { class: "chip" }, h("i", { class: "chip-dot" }), h("span", { text: label }));
  requestAnimationFrame(() => chip.classList.add("settled"));
  return chip;
}

function sameChoice(a: ModelChoice, b: ModelChoice): boolean {
  if (a === "auto" || b === "auto") return a === b;
  return a.provider === b.provider && a.model === b.model;
}

/** What the chat reaches outside its own view: the saved conversations, the chat's Rust backend and the model that answers the field. The app passes its own; the dev sample passes stand-ins. */
export interface ChatDeps {
  store: StoreBackend;
  chat: ChatBackend;
  resolve: (feature: Feature) => Promise<Resolution | null>;
}

const appDeps: ChatDeps = { store: bridgeStore, chat: bridgeChat, resolve: (feature) => Bridge.aiResolve(feature) };

export function buildPrompt(actions: ChatActions, onHeightChange: () => void, link: ChatLink): ViewHost & { refreshModel(): Promise<void> } {
  return buildChat(actions, onHeightChange, link, appDeps);
}

/** The chat with its outside reached through `deps` (the dev sample's stand-ins; the app uses buildPrompt). `refreshModel` reads the model the field shows again. */
export function buildChat(actions: ChatActions, onHeightChange: () => void, link: ChatLink, deps: ChatDeps): ViewHost & { refreshModel(): Promise<void> } {
  // The store and the chat backend are the app's, or the dev sample's stand-ins (deps): the names below are the app's own, so every call reads the same way.
  const bridgeStore: StoreBackend = deps.store;
  const bridgeChat: ChatBackend = deps.chat;
  const chipRow = h("div", { class: "chip-row" });
  const fileChipSlot = h("span", {});
  const modelChipEl = h("button", { class: "chip model-chip", title: "Which model answers" });
  // What Claude may do in this chat (only when Claude Code is the engine): Chat only, Read-only or Agent.
  const levelChipEl = h("button", { class: "chip level-chip", title: FOLDER_TITLE });
  // The conversations menu, first in the row. It is off while a reply runs: a new chat or an opened conversation would cancel it (Rust's ai_load_turns).
  const menuChipEl = h("button", { class: "chip settled", title: "Conversations and new chat", text: "⋯" });
  chipRow.append(menuChipEl, fileChipSlot, levelChipEl, modelChipEl);
  const log = h("div", { class: "chat-log" });
  // One line while the last autosave was refused (see autosave); it is a note in the chat's own style.
  const unsavedEl = h("div", { class: "chat-note", style: "display: none;", text: UNSAVED_NOTE });
  const menu = h("div", { class: "model-picker" });
  const listPane = h("div", { class: "model-picker cm-pane" });
  const picker = h("div", { class: "model-picker" });
  const levelPicker = h("div", { class: "model-picker" });
  // Shown instead of the chat while it is in its own window (the pop-out): one line and the way back.
  const poppedEl = h("div", { class: "chat-note", style: "display: none;" },
    h("span", { text: POPPED_OUT_NOTE }),
    h("button", { class: "btn secondary", text: BRING_BACK, onclick: () => void Bridge.hideChatWindow() }));
  const input = h("input", {
    type: "text",
    class: "chat-input",
    placeholder: "Ask me anything…",
    spellcheck: "false",
  }) as HTMLInputElement;
  const send = h("button", { class: "send-btn", title: "Send" }, svg(ICONS.arrowUp, 11));
  const bar = h("div", { class: "chat-bar" }, input, send);
  // The quick card (Fix, Rewrite) above the field: hidden until a quick action has a reply or a line to show.
  const quickEl = h("div", { class: "cm-quick", style: "display: none;" });

  const el = h(
    "div",
    { class: "view" },
    h("div", { class: "card wash chat-card" }, h("div", { class: "chat-body" }, poppedEl, chipRow, menu, unsavedEl, log, listPane, picker, levelPicker, quickEl, bar)),
  );
  (el.querySelector(".card") as HTMLElement).style.setProperty("--wash", "rgba(99,102,241,0.5)");

  let sending = false;
  let renderedKey = "";
  let resolution: Resolution | null = null;
  let showGuide = false;
  let pickerOpen = false;
  let levelPickerOpen = false;
  let menuOpen = false;
  // The Conversations pane: in place of the log while it is open. `heads` is the store's list; a rename in progress keeps its row.
  let pane: "chat" | "list" = "chat";
  let heads: Head[] = [];
  let listNote = "";
  let renamingId: string | null = null;
  let confirmingAll = false;
  let drawnSending: boolean | null = null;
  let countdown: { note: ChatMessage; left: number; timer: number; files: string[] } | null = null;
  let quickDrawn = "";
  /** The Claude Code session of the running quick action (Claude plan), registered as the chat's; forgotten at the next quick action or after its grace. */
  let quickSession: string | null = null;
  let quickSessionTimer = 0;
  /** The conversation generation (State.chatEpoch) whose autosave was refused, or null. A new chat changes the generation, so the line goes with it. */
  let unsavedAt: number | null = null;

  /** The brain a send will use: the feature it really runs under, or the one the waiting file and the conversation imply. */
  async function refreshModel(feature: Feature = nextFeature()) {
    resolution = await deps.resolve(feature);
    modelChipEl.textContent = chipLabel(resolution, State.claudeStatus?.authMethod ?? null, State.claudePaidBy);
    State.notify();
  }

  /**
   * The autosave after a kept reply. A refused save shows UNSAVED_NOTE until a save works or the chat is new. A save that lands after a new chat started
   * is not this chat's, so it changes nothing.
   */
  function autosave() {
    const epoch = State.chatEpoch;
    void saveCurrent(bridgeStore, Date.now()).then((ok) => {
      if (epoch !== State.chatEpoch) return;
      unsavedAt = ok ? null : epoch;
      State.notify();
    });
  }

  function stopCountdown() {
    if (!countdown) return;
    window.clearInterval(countdown.timer);
    State.chatHistory = State.chatHistory.filter((m) => m !== countdown!.note);
    countdown = null;
  }

  /** Rust took the user's message back, so the dropped file it carried goes back to waiting for the next send. */
  function giveBack(files: string[]) {
    if (files.length && !State.pendingAttachment) State.pendingAttachment = files[0];
  }

  /** The user gave up on a retry countdown: the file the failed message carried waits for the next send. */
  function cancelCountdown() {
    if (countdown) giveBack(countdown.files);
    stopCountdown();
  }

  function note(content: string, action: AiAction | null = null): ChatMessage {
    const m: ChatMessage = { id: nextMessageId(), role: "note", content, action };
    State.chatHistory.push(m);
    return m;
  }

  function runAction(action: AiAction) {
    switch (action.kind) {
      case "openSettings":
        actions.openSettingsWindow("chat/keys");
        break;
      case "openBilling":
        actions.openUrl(action.url);
        break;
      case "openGuide":
        showGuide = true;
        break;
      case "chooseModel":
        void openPicker();
        break;
      case "cancel":
        cancelCountdown();
        break;
      case "signInClaude":
        void Bridge.claudeSignIn().then((opened) => {
          if (!opened) note("Open a terminal and run: claude auth login");
          State.notify();
        });
        break;
      case "installClaude":
      case "updateClaude":
        actions.openUrl(INSTALL_GUIDE);
        break;
      case "installGit":
        actions.openUrl(GIT_FOR_WINDOWS);
        break;
      case "tryAgain": {
        // The message that got no answer goes again.
        const last = [...State.chatHistory].reverse().find((m) => m.role === "user");
        if (last) {
          State.chatHistory = State.chatHistory.filter((m) => m !== last);
          input.value = last.content;
          submit();
        }
        break;
      }
    }
    State.notify();
    onHeightChange();
  }

  interface Ask {
    text: string;
    attachments: string[];
    feature: Feature;
    regenerate: boolean;
    retries: number;
    /** The companion's text for this turn; the default is built from the island's state when it is sent. */
    system?: string;
    /** A quick action's turn (Explain this screenshot): a refused picture gets the quick words. */
    quick?: boolean;
  }

  async function ask(req: Ask) {
    if (sending) return;
    // The companion's text is built before the thinking override is set, so the mood it reads is the Main cat's own (sleeping, finished, error...).
    let system: string;
    try {
      system = req.system ?? systemFor(link.context(), State.settings, localDay(new Date()));
    } catch (err) {
      giveBack(req.attachments);
      note(String(err).replace(/^Error:\s*/, ""));
      Sound.play("error");
      State.notify();
      onHeightChange();
      return;
    }
    sending = true;
    // A drop or a new chat bumps this; a turn that started before it must not touch the new conversation.
    const epoch = State.chatEpoch;
    const stale = () => State.chatEpoch !== epoch;
    stopCountdown();
    showGuide = false;
    const reply: ChatMessage = {
      id: nextMessageId(), role: "assistant", content: "", status: "streaming", sources: [], notices: [], feature: req.feature,
    };
    let waking = 0;
    State.stateOverride = "thinking";
    State.notify();
    onHeightChange();

    const settle = () => {
      if (State.stateOverride === "thinking") State.stateOverride = null;
      window.clearTimeout(waking);
    };

    const onEvent = (e: AiEvent) => {
      if (stale()) return;
      switch (e.type) {
        case "claudeSession":
          // The chat learns its Claude Code session before anything runs: its hook events are the chat's.
          link.session(e.sessionId, e.retired);
          break;
        case "step": {
          const { type: _type, ...step } = e;
          const steps = reply.steps ?? [];
          const at = steps.findIndex((s) => s.id === step.id);
          if (at >= 0) steps[at] = step;
          else steps.push(step);
          reply.steps = steps;
          if (!State.chatHistory.includes(reply)) State.chatHistory.push(reply);
          break;
        }
        case "engine":
          State.claudePaidBy = e.paidBy;
          break;
        case "started":
          reply.caption = e.caption;
          if (!State.chatHistory.includes(reply)) State.chatHistory.push(reply);
          window.clearTimeout(waking);
          if (e.waking) {
            const line = e.waking;
            waking = window.setTimeout(() => {
              if (reply.content) return;
              reply.notices = [...(reply.notices ?? []), line];
              actions.emote("yawn");
              State.notify();
            }, WAKING_AFTER_MS);
          }
          break;
        case "delta":
          reply.content += e.text;
          settle();
          break;
        case "citation":
          if (!reply.sources?.some((s) => s.url === e.url)) reply.sources = [...(reply.sources ?? []), { url: e.url, title: e.title }];
          break;
        case "notice":
          if (!reply.notices?.includes(e.text)) reply.notices = [...(reply.notices ?? []), e.text];
          break;
        case "done":
          settle();
          reply.content = e.text || reply.content;
          reply.status = e.interrupted ? "interrupted" : e.cancelled ? "stopped" : undefined;
          // A step that never finished (Stop, a crash) ends as stopped: no row stays "running".
          if (reply.steps) reply.steps = endUnfinished(reply.steps);
          // Drop the "waking up" line once the model has spoken.
          reply.notices = (reply.notices ?? []).filter((n) => !n.startsWith("Waking up"));
          // Stop during Claude Code's work keeps the steps it took, even with no words yet.
          if (!reply.content && !reply.steps?.length) {
            State.chatHistory = State.chatHistory.filter((m) => m !== reply);
            if (e.cancelled) giveBack(req.attachments);
          }
          // A kept reply is saved with its conversation (the store keeps 50); a reply that was taken back is not.
          if (State.chatHistory.includes(reply)) autosave();
          // An empty reply never gets here (Rust sends a problem instead), but the sound is the last thing to trust.
          if (!e.cancelled && !e.interrupted && reply.content.trim()) Sound.play("finish");
          break;
        // `error`: a provider or the network failed. `problem`: the island's own notice (a file it
        // can't read, an empty reply). Both are shown the same way: a note and the error sound.
        case "problem":
        case "error": {
          settle();
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          Sound.play("error");
          // The cat shows its error face once, or the rate-limit look for the plan's limit; it never loops on an error.
          State.stateOverride = e.type === "error" && e.resetsAt != null ? "ratelimit" : "error";
          window.setTimeout(() => {
            if (State.stateOverride === "error") State.stateOverride = null;
            State.notify();
          }, 1500);
          // The plan's limit says when it resets, in the viewer's time zone.
          const text = e.type === "error" ? planLimitNote(e.message, e.resetsAt) : req.quick ? quickNote(e) : e.message;
          const n = note(text, e.action);
          const wait = e.type === "error" ? e.retryAfter : null;
          const retrying = wait != null && req.retries < MAX_AUTO_RETRIES;
          // A countdown re-asks with the same files; without one the next send must carry them.
          // A file Rust refuses at send time (it changed or vanished since the drop) is forgotten, chip
          // included: giving it back would make every next message carry the same refused file.
          if (e.type === "problem" && e.kind === "rejected") forgetDrop(State);
          else if (!retrying) giveBack(req.attachments);
          if (retrying) {
            const left = wait;
            const timer = window.setInterval(() => {
              if (!countdown) return;
              if (stale()) {
                stopCountdown();
                return;
              }
              countdown.left -= 1;
              n.content = e.message.replace(/in \d+ s\./, `in ${countdown.left} s.`);
              if (countdown.left <= 0) {
                stopCountdown();
                void ask({ ...req, retries: req.retries + 1 });
              }
              State.notify();
            }, 1000);
            countdown = { note: n, left, timer, files: req.attachments };
          } else if (wait != null) {
            // Out of automatic retries: no frozen countdown, just the provider's name and a plain "try again".
            n.content = stillBusy(e.message);
            n.action = null;
          }
          break;
        }
        case "emptyState": {
          settle();
          // Nothing could answer: take the message back so it isn't lost, and show the way out.
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          const last = State.chatHistory.at(-1);
          if (last?.role === "user" && last.content === req.text) {
            State.chatHistory.pop();
            input.value = req.text;
          }
          giveBack(req.attachments);
          resolution = { ...(resolution ?? ({} as Resolution)), empty: true };
          break;
        }
      }
      State.notify();
      onHeightChange();
    };

    try {
      await Bridge.aiChat(req.feature, req.text, req.attachments, req.regenerate, system, req.quick === true, onEvent);
    } catch (err) {
      settle();
      if (stale()) return;
      State.chatHistory = State.chatHistory.filter((m) => m !== reply);
      giveBack(req.attachments);
      note(String(err).replace(/^Error:\s*/, ""));
      Sound.play("error");
    } finally {
      settle();
      sending = false;
      State.notify();
      onHeightChange();
      input.focus();
      void refreshModel();
    }
  }

  /** The status question and its answer, from the ledger. NotchMeow's own card, in `State.localAnswers`: not a message, not in the conversation, not sent to anything. */
  function answerLocally(text: string): boolean {
    const sk = Hub.sk;
    if (!sk) return false;
    const a = answerStatus(text, sk, State.chatHistory.length, nextMessageId());
    if (!a) return false;
    State.localAnswers.push(a);
    State.notify();
    onHeightChange();
    // The template is on screen. A model on this computer may offer a nicer wording by the same rules as a note's; it never leaves this computer.
    void sk.polishLines(a.lines, a.facts).then((next) => {
      if (next === null || !State.localAnswers.includes(a)) return;
      a.lines = next;
      State.notify();
    });
    return true;
  }

  function localCard(a: LocalAnswer): HTMLElement[] {
    return [
      h("div", { class: "chat-row user" }, h("div", { class: "bubble", text: a.question })),
      h("div", { class: "chat-row" }, h("div", { class: "reply-col" }, ...a.lines.map((l) => h("div", { class: "reply", text: l })), h("div", { class: "reply-caption", text: STATUS_CAPTION }))),
    ];
  }

  /** The one-time cloud line before a turn, as a send shows it (submit and the quick flows). */
  function cloudNoticeNow() {
    const notice = cloudLine(resolution, State.settings.companion);
    if (!notice) return;
    note(notice.line);
    State.settings.companion.cloudNoticeShown = notice.shown;
    void Bridge.saveSettings(State.settings);
  }

  /** True from a message being pushed until `ask` has taken over `sending`, so a second Send in that gap is not a second message. */
  let submitting = false;

  async function submit() {
    if (submitting) return;
    if (sending) {
      void Bridge.aiCancel();
      // Whatever Claude Code was waiting to do is refused, and the card goes.
      link.release();
      return;
    }
    // A running quick action holds the one reply at a time: Send waits, and the text stays in the field.
    if (State.quickResult?.running) return;
    const text = input.value.trim();
    if (!text) return;
    // A page with no Sidekick (the pop-out window) cannot answer the status question from the ledger, and the question never reaches a model: a note says where to ask, and the field keeps the text.
    if (!Hub.sk && matchStatusQuestion(text).matched) {
      note(STATUS_IN_ISLAND_NOTE);
      State.notify();
      onHeightChange();
      return;
    }
    input.value = "";
    // "What's Claude doing?" is answered here, on this computer, before any model is chosen or any file is read: it never reaches a model (sub-project F1).
    if (answerLocally(text)) return;
    Sound.play("send");
    cancelCountdown(); // a message sent over a waiting retry replaces it, and takes its file along
    const attachments = pendingAttachments();
    State.pendingAttachment = null;
    // This message and the conversation before it decide: once a file is in the conversation, every
    // message uses File questions, so the file's text never reaches a model the user didn't pick for files.
    const feature = featureFor(attachments, State.chatHistory);
    State.chatHistory.push({ id: nextMessageId(), role: "user", content: text, attachments });
    // The model is read again first, so the cloud line names the brain this send will really use (none: no line).
    submitting = true;
    try {
      await refreshModel(feature);
    } finally {
      submitting = false;
    }
    // The first answer from a brain that is in the cloud says so once per provider (the Companion's one-time notice), and is kept.
    cloudNoticeNow();
    void ask({ text, attachments, feature, regenerate: false, retries: 0 });
  }

  function continueOrRetry(m: ChatMessage, how: "continue" | "retry") {
    // Both belong to the reply they extend, so they use the setting that reply used.
    const feature = m.feature ?? "chat";
    if (how === "continue") {
      State.chatHistory.push({ id: nextMessageId(), role: "user", content: "Continue" });
      void ask({ text: "Continue", attachments: [], feature, regenerate: false, retries: 0 });
    } else {
      State.chatHistory = State.chatHistory.filter((x) => x !== m);
      void ask({ text: "", attachments: [], feature, regenerate: true, retries: 0 });
    }
  }

  // ── Quick actions: Fix and Rewrite show their reply in the card; Explain is a normal chat turn ──

  function closeQuick() {
    // A running quick action is stopped with the card: its turn holds the one reply gate until it ends.
    if (State.quickResult?.running) void Bridge.aiCancel();
    State.quickResult = null;
    State.notify();
    onHeightChange();
  }

  async function copyQuick(q: QuickResult) {
    const copied = await Bridge.copyText(q.text);
    if (!copied) q.note = QUICK_TOO_LONG;
    State.notify();
  }

  /** The card: its title, the reply as plain text (never HTML), the cut note, Copy once the reply is in, and ×. */
  function drawQuick(q: QuickResult | null) {
    clear(quickEl);
    if (!q) return;
    quickEl.append(h("div", { class: "cm-quick-title", text: QUICK_TITLES[q.kind] }));
    if (q.running && !q.text) quickEl.append(typingDots());
    if (q.text) quickEl.append(h("div", { class: "reply cm-quick-text", text: q.text }));
    if (q.cut) quickEl.append(h("div", { class: "reply-meta", text: CUT_NOTE }));
    if (q.note) quickEl.append(h("div", { class: "chat-note", text: q.note }));
    const actions = h("div", { class: "cm-quick-actions" });
    if (q.text && !q.running) actions.append(smallButton(QUICK_COPY, () => void copyQuick(q)));
    actions.append(h("button", { class: "note-btn", text: "×", title: QUICK_CLOSE, onclick: closeQuick }));
    quickEl.append(actions);
  }

  /** Fix or Rewrite of the field's text, read when chosen: one quick turn (Rust's ai_quick), its reply shown in the card. The chat's conversation is not touched. */
  async function quickFix(kind: "fix" | "rewrite") {
    menuOpen = false;
    const r = quickRequest(kind, input.value, "pc");
    if (sending || !r) {
      State.notify();
      onHeightChange();
      return;
    }
    forgetQuickSession();
    const card: QuickResult = { kind, text: "", running: true, cut: r.cut, note: null };
    let streamed = "";
    State.quickResult = card;
    State.notify();
    onHeightChange();
    try {
      await Bridge.aiQuick("chat", r.system, r.user, [], (e) => {
        // A Claude plan run names its session first: it is the chat's, so its hook events are never a pill's (the chat's own rule, handleHook).
        if (e.type === "claudeSession") {
          quickSession = e.sessionId;
          link.session(e.sessionId, e.retired);
          return;
        }
        if (State.quickResult !== card) return;
        if (e.type === "delta") {
          streamed += e.text;
          card.text = streamed;
        } else if (e.type === "done") {
          card.text = quickResultClean(kind, e.text || streamed);
          card.running = false;
        } else if (e.type === "error" || e.type === "problem") {
          card.note = quickNote(e);
          card.running = false;
        } else if (e.type === "emptyState") {
          card.note = NO_MODEL_NOTE;
          card.running = false;
        }
        State.notify();
        onHeightChange();
      });
    } catch (err) {
      card.note = String(err).replace(/^Error:\s*/, "");
    } finally {
      card.running = false;
      // One-shot grace after a run that registered a session; nothing is armed when no session ran.
      if (quickSession !== null) quickSessionTimer = window.setTimeout(forgetQuickSession, QUICK_SESSION_GRACE_MS);
      State.notify();
      onHeightChange();
    }
  }

  /** Drops the quick action's Claude Code session from the chat's sessions (now, or from the grace timer). */
  function forgetQuickSession() {
    window.clearTimeout(quickSessionTimer);
    quickSessionTimer = 0;
    if (quickSession !== null) link.forget(quickSession);
    quickSession = null;
  }

  /** Explain the field's text: the conversation is saved, a new chat starts, and the explanation is a normal chat turn. A waiting file stays waiting. */
  async function explainText() {
    menuOpen = false;
    const shown = input.value.trim();
    const r = quickRequest("explain", shown, "pc");
    if (sending || State.quickResult?.running || !r) {
      State.notify();
      onHeightChange();
      return;
    }
    input.value = "";
    await saveCurrent(bridgeStore, Date.now());
    const restore = keepWaiting(State);
    startNewChat(link, bridgeChat);
    State.claudeLevel = { level: "none", folder: null };
    restore();
    State.chatHistory.push({ id: nextMessageId(), role: "user", content: shown });
    await refreshModel("chat");
    cloudNoticeNow();
    void ask({ text: r.user, attachments: [], feature: "chat", regenerate: false, retries: 0, system: r.system, quick: true });
  }

  /** The screenshot chip: a new chat that explains the waiting picture. The picture is taken before the new chat forgets it, and the new turn carries it. */
  async function explainScreenshot() {
    const shot = State.pendingAttachment;
    const r = quickRequest("explainImage", "", "pc");
    if (sending || State.quickResult?.running || !r || !shot) return;
    menuOpen = false;
    const restore = keepWaiting(State);
    startNewChat(link, bridgeChat);
    State.claudeLevel = { level: "none", folder: null };
    restore();
    State.pendingAttachment = null;
    const attachments = [shot];
    State.chatHistory.push({ id: nextMessageId(), role: "user", content: r.user, attachments });
    await refreshModel("files");
    cloudNoticeNow();
    void ask({ text: r.user, attachments, feature: "files", regenerate: false, retries: 0, system: r.system, quick: true });
  }

  /** A picture pasted into the field becomes the waiting file, as a drop's copy does, and the conversation stays. Only a PNG is taken; any other paste is text. */
  async function takePicture(picture: File) {
    try {
      const file = await Bridge.ingestPng(new Uint8Array(await picture.arrayBuffer()));
      State.droppedFile = { name: file.name, path: file.path };
      State.promptContext = { kind: "file", name: file.name, path: file.path };
      State.pendingAttachment = file.path;
      State.notify();
      // The picture is waiting, so the model chip and the cloud line describe the files feature.
      await refreshModel();
      State.dropReader = resolution?.reader ?? null;
    } catch (err) {
      note(String(err).replace(/^Error:\s*/, ""));
    }
    State.notify();
    onHeightChange();
  }

  input.addEventListener("paste", (e) => {
    const picture = Array.from(e.clipboardData?.files ?? []).find((f) => f.type === "image/png");
    if (!picture) return;
    e.preventDefault();
    void takePicture(picture);
  });

  // ── Model picker ────────────────────────────────────────────────────────────

  let pickerClouds: Parameters<typeof renderPicker>[0] | null = null;
  let pickerServers: AiServer[] = [];

  async function openPicker() {
    pickerOpen = true;
    pickerClouds = null;
    clear(picker);
    picker.append(h("div", { class: "picker-head", text: "Looking for models…" }));
    State.notify();
    onHeightChange();
    const [, keyed] = await Promise.all([
      Bridge.aiDiscover().then((s) => { pickerServers = s ?? []; }),
      Promise.all(CLOUD_PROVIDERS.map(async (c) => ((await Bridge.secretPresent(c.key)) ? c : null))),
    ]);
    const clouds = keyed.filter((c): c is (typeof CLOUD_PROVIDERS)[number] => c !== null);
    const lists = await Promise.all(
      clouds.map(async (c) => ({ c, models: await Bridge.aiListModels(c.id).catch(() => []) })),
    );
    renderPicker(lists, pickerServers);
  }

  // The added server can answer after the picker is drawn (a slow LAN host): Rust sends the full list
  // when its check ends, and an open picker redraws with it.
  void onEvent<AiServer[]>("ai-servers-changed", (s) => {
    pickerServers = s;
    if (pickerOpen && pickerClouds) renderPicker(pickerClouds, s);
  });

  function renderPicker(
    clouds: { c: (typeof CLOUD_PROVIDERS)[number]; models: { id: string; displayName: string }[] }[],
    servers: AiServer[],
  ) {
    pickerClouds = clouds;
    pickerServers = servers;
    clear(picker);
    const f = nextFeature();
    const current = State.settings.ai[f];
    const option = (label: string, choice: ModelChoice) =>
      h("button", {
        class: sameChoice(current, choice) ? "picker-item on" : "picker-item",
        text: label,
        onclick: () => {
          State.settings.ai = { ...State.settings.ai, [f]: choice };
          void Bridge.saveSettings(State.settings);
          pickerOpen = false;
          void refreshModel();
          onHeightChange();
        },
      });
    picker.append(option("Auto", "auto"));
    if (State.settings.ai.claudeCodeEnabled && State.claudeStatus?.state === "signedIn") {
      picker.append(h("div", { class: "picker-head", text: "Claude plan" }));
      for (const m of ["sonnet", "opus", "haiku"]) {
        picker.append(option(`Claude plan · ${m[0].toUpperCase()}${m.slice(1)}`, { provider: "claudeCode", model: m }));
      }
    }
    if (clouds.length) picker.append(h("div", { class: "picker-head", text: "Cloud" }));
    for (const { c, models } of clouds) {
      for (const m of models) picker.append(option(`${c.brand} · ${m.displayName}`, { provider: c.id, model: m.id }));
    }
    const running = servers.filter((s) => s.status === "running" && s.models.length);
    if (running.length) picker.append(h("div", { class: "picker-head", text: "Local" }));
    for (const s of running) {
      for (const m of s.models) picker.append(option(`${s.name} · ${m.id}`, { provider: s.provider, model: m.id }));
    }
    State.notify();
    onHeightChange();
  }

  modelChipEl.addEventListener("click", () => {
    if (pickerOpen) {
      pickerOpen = false;
      State.notify();
      onHeightChange();
    } else {
      levelPickerOpen = false;
      menuOpen = false;
      void openPicker();
    }
  });

  // ── Level picker (Claude Code only) ─────────────────────────────────────────

  /** Whether Claude Code is the engine that answers the next message. */
  const usesClaude = () => resolution?.provider === "claudeCode";

  async function chooseLevel(level: ClaudeLevel, folder: string | null) {
    try {
      State.claudeLevel = (await Bridge.claudeSetLevel(level, folder)) ?? State.claudeLevel;
      levelPickerOpen = false;
    } catch (err) {
      note(String(err).replace(/^Error:\s*/, ""));
    }
    State.notify();
    onHeightChange();
  }

  /** The folder Claude may work in: the system's dialog, else the path typed in. */
  async function drawLevelPicker() {
    const hooksReady = (await Bridge.hooksStatus())?.installed ?? false;
    // Cleared after the await, so two quick toggles rebuild the rows once each, never double them.
    clear(levelPicker);
    const row = (label: string, detail: string, level: ClaudeLevel, enabled = true) =>
      h("button", {
        class: State.claudeLevel.level === level ? "picker-item on" : "picker-item",
        text: `${label} — ${detail}`,
        disabled: !enabled,
        onclick: async () => {
          if (level === "chat") return void chooseLevel("chat", null);
          const picked = await Bridge.claudePickFolder();
          if (picked) return void chooseLevel(level, picked);
          // No dialog here (or it was cancelled): ask for the path as text.
          pathRow(level);
        },
      });
    function pathRow(level: ClaudeLevel) {
      levelPicker.querySelector(".picker-path")?.remove();
      const path = h("input", { type: "text", class: "chat-input", placeholder: "Folder path", spellcheck: "false" }) as HTMLInputElement;
      const use = h("button", { class: "note-btn", text: "Use it", onclick: () => void chooseLevel(level, path.value.trim()) });
      levelPicker.append(h("div", { class: "picker-path" }, path, use));
      path.focus();
      onHeightChange();
    }
    levelPicker.append(
      row(FOLDER_ROWS[0], "answers, dropped files, web search", "chat"),
      row(FOLDER_ROWS[1], "also reads files in a folder you choose", "read"),
      row(FOLDER_ROWS[2], "also edits files and runs commands there, each behind a card", "agent", hooksReady),
    );
    if (!hooksReady) {
      levelPicker.append(h("div", { class: "picker-head", text: "Agent needs NotchMeow's hooks in Claude Code, or every step is refused. Install them in Settings." }));
    }
    onHeightChange();
  }

  levelChipEl.addEventListener("click", () => {
    if (sending) return;
    levelPickerOpen = !levelPickerOpen;
    if (levelPickerOpen) {
      pickerOpen = false;
      menuOpen = false;
      void drawLevelPicker();
    }
    State.notify();
    onHeightChange();
  });

  // ── Conversations (the ⋯ menu): a new chat, the saved list, rename, pin, delete ─

  menuChipEl.addEventListener("click", () => {
    if (sending) return;
    menuOpen = !menuOpen;
    if (menuOpen) {
      pickerOpen = false;
      levelPickerOpen = false;
    }
    State.notify();
    onHeightChange();
  });
  const newChatItem = h("button", { class: "picker-item", text: MENU.newChat, onclick: () => newChat() });
  menu.append(newChatItem, h("button", { class: "picker-item", text: MENU.conversations, onclick: () => void openList() }));
  // Fix and Rewrite (the card above the field) and Explain (a new chat, a normal turn). Off with an empty field, and while a reply or a quick action runs.
  const fixItem = h("button", { class: "picker-item", text: MENU.fix, onclick: () => void quickFix("fix") });
  const rewriteItem = h("button", { class: "picker-item", text: MENU.rewrite, onclick: () => void quickFix("rewrite") });
  const explainItem = h("button", { class: "picker-item", text: MENU.explain, onclick: () => void explainText() });
  menu.append(fixItem, rewriteItem, explainItem);
  // Pop out: the conversation is saved, the chat goes to its own window and the island folds. Off while a reply streams (it would be cut off by the window's load of the saved turns).
  const popOutItem = h("button", { class: "picker-item", text: MENU.popOut, onclick: () => void popOut() });
  if (actions.collapse) menu.append(popOutItem);

  async function popOut() {
    if (sending) return;
    menuOpen = false;
    // A chat that cannot be saved stays here: the window opens a conversation from its file.
    const hasWords = State.chatHistory.some((m) => m.role === "user");
    if (!(await saveCurrent(bridgeStore, Date.now())) && hasWords) {
      note("The chat couldn't be saved, so it stays here.");
      State.notify();
      onHeightChange();
      return;
    }
    State.chatPoppedOut = true;
    if (!(await Bridge.showChatWindow(State.chatId))) {
      State.chatPoppedOut = false;
      note("The chat window couldn't open.");
      State.notify();
      onHeightChange();
      return;
    }
    State.notify();
    actions.collapse?.();
  }

  function leaveList() {
    pane = "chat";
    renamingId = null;
    confirmingAll = false;
    listNote = "";
  }

  function newChat() {
    if (sending) return;
    menuOpen = false;
    leaveList();
    startNewChat(link, bridgeChat);
    State.notify();
    onHeightChange();
  }

  /** The store's list, read again; the rows are rebuilt with it. */
  async function refreshList() {
    heads = await bridgeStore.list();
    drawList();
    onHeightChange();
  }

  async function openList() {
    menuOpen = false;
    pickerOpen = false;
    levelPickerOpen = false;
    leaveList();
    pane = "list";
    State.notify();
    onHeightChange();
    await refreshList();
  }

  function backToChat() {
    leaveList();
    State.notify();
    onHeightChange();
  }

  /** Opens a row's conversation. A failed open leaves the chat as it was and says so in it. */
  async function openRow(id: string) {
    if (sending) return;
    const ok = await openConversation(bridgeStore, id, link, bridgeChat);
    leaveList();
    if (!ok) note(OPEN_FAILED_NOTE);
    State.notify();
    onHeightChange();
  }

  /** The pin, or the pane's one line when it was refused (the cap, or the file could not be written). The rows stay as they were. */
  async function pinRow(id: string) {
    const r = await togglePin(bridgeStore, id, Date.now());
    renamingId = null;
    listNote = r === "full" ? LIST_NOTES.pinFull : r === "failed" ? LIST_NOTES.pin : "";
    await refreshList();
  }

  async function deleteRow(id: string) {
    const ok = await removeOne(bridgeStore, id, link, bridgeChat);
    renamingId = null;
    listNote = ok ? "" : LIST_NOTES.deleteOne;
    State.notify();
    await refreshList();
  }

  async function deleteAll() {
    confirmingAll = false;
    const ok = await removeAll(bridgeStore, link, bridgeChat);
    listNote = ok ? "" : LIST_NOTES.deleteAll;
    State.notify();
    await refreshList();
  }

  /** A row being renamed: its title in a field, which keeps Escape for itself. Enter saves; an empty title changes nothing. */
  function renameRow(c: Head): HTMLElement {
    const field = h("input", { type: "text", class: "chat-input", spellcheck: "false" }) as HTMLInputElement;
    field.value = c.title;
    const save = async () => {
      const t = field.value.trim();
      renamingId = null;
      listNote = "";
      if (t && !(await rename(bridgeStore, c.id, t, Date.now()))) listNote = LIST_NOTES.rename;
      await refreshList();
    };
    field.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") {
        e.preventDefault();
        void save();
      }
      e.stopPropagation(); // Escape closes the island, not the rename
    });
    return h(
      "div",
      { class: "picker-path" },
      field,
      h("button", { class: "note-btn", text: PANE.save, onclick: () => void save() }),
      h("button", { class: "note-btn", text: PANE.cancel, onclick: () => { renamingId = null; drawList(); } }),
    );
  }

  /** One saved conversation: its title opens it (not while a reply runs), the pin and the rename and delete are beside it. */
  function listRow(c: Head): HTMLElement {
    if (renamingId === c.id) return renameRow(c);
    return h(
      "div",
      { class: "picker-path" },
      h("button", { class: "picker-item", text: c.title, style: "flex: 1 1 auto; min-width: 0;", disabled: sending, onclick: () => void openRow(c.id) }),
      c.pinned ? h("span", { class: "reply-caption", text: PANE.pinned }) : null,
      h("button", { class: "note-btn", text: c.pinned ? PANE.unpin : PANE.pin, onclick: () => void pinRow(c.id) }),
      h("button", { class: "note-btn", text: PANE.rename, onclick: () => { renamingId = c.id; listNote = ""; drawList(); } }),
      h("button", { class: "note-btn", text: PANE.delete, onclick: () => void deleteRow(c.id) }),
    );
  }

  /** The Conversations pane, built from `heads`. Called when the data or the pane's own state changes, never on a plain redraw. */
  function drawList() {
    drawnSending = sending;
    clear(listPane);
    // The back line and the note stay at the top, the rows scroll in their own box, and the footer (Delete all, or its confirm) stays in view at the bottom.
    const rows = h("div", { class: "cm-pane-rows" });
    const foot = h("div", { class: "cm-pane-foot" });
    listPane.append(h("div", { class: "picker-path" }, h("button", { class: "note-btn", text: PANE.back, onclick: backToChat })));
    if (listNote) listPane.append(h("div", { class: "chat-note", text: listNote }));
    if (heads.length === 0) rows.append(h("div", { class: "chat-note", text: "No saved conversations yet." }));
    const byId = new Map(heads.map((c) => [c.id, c]));
    for (const id of conversationsKeep(heads).keep) {
      const c = byId.get(id);
      if (c) rows.append(listRow(c));
    }
    if (heads.length > 0) {
      if (confirmingAll) {
        foot.append(
          h(
            "div",
            { class: "chat-note" },
            h("span", { text: `Delete all ${heads.length} conversations? This can't be undone.` }),
            h("button", { class: "note-btn", text: PANE.cancel, onclick: () => { confirmingAll = false; drawList(); } }),
            h("button", { class: "btn primary", text: PANE.delete, disabled: sending, onclick: () => void deleteAll() }),
          ),
        );
      } else {
        foot.append(h("button", { class: "note-btn", text: PANE.deleteAll, onclick: () => { confirmingAll = true; drawList(); } }));
      }
    }
    listPane.append(rows, foot);
    // A row being renamed takes the focus when the pane is built.
    if (renamingId !== null) listPane.querySelector<HTMLInputElement>(".chat-input")?.focus();
  }

  // ── Rendering ───────────────────────────────────────────────────────────────

  function smallButton(label: string, onclick: () => void): HTMLElement {
    return h("button", { class: "note-btn", text: label, onclick });
  }

  function actionLabel(a: AiAction): string {
    switch (a.kind) {
      case "openSettings": return "Open Settings";
      case "openBilling": return "Open billing page";
      case "openGuide": return "Open guide";
      case "chooseModel": return "Choose model";
      case "cancel": return "Cancel";
      case "signInClaude": return "Sign in";
      case "installClaude": return "How to install";
      case "updateClaude": return "How to update";
      case "installGit": return "Get Git for Windows";
      case "tryAgain": return "Try again";
    }
  }

  function bubble(m: ChatMessage): HTMLElement {
    if (m.role === "user") {
      return h("div", { class: "chat-row user" }, h("div", { class: "bubble", text: m.content }));
    }
    if (m.role === "note") {
      const action = m.action;
      return h(
        "div",
        { class: "chat-row" },
        h("div", { class: "chat-note" }, h("span", { text: m.content }), action ? smallButton(actionLabel(action), () => runAction(action)) : null),
      );
    }
    const col = h("div", { class: "reply-col" });
    // Steps Claude Code took: one row each, in the island's own words.
    if (m.steps?.length) {
      col.append(h("div", { class: "reply-steps" }, ...m.steps.map((s) => h("div", { class: `step-row ${s.state}`, text: stepRow(s) }))));
    }
    if (m.content) col.append(h("div", { class: "reply" }, renderBlocks(parseMarkdown(m.content), actions.openUrl)));
    if (m.status === "interrupted" && m === State.chatHistory.at(-1)) {
      col.append(
        h("div", { class: "reply-meta" }, h("span", { text: "interrupted" }),
          smallButton("Continue", () => continueOrRetry(m, "continue")),
          smallButton("Retry", () => continueOrRetry(m, "retry"))),
      );
    }
    for (const n of m.notices ?? []) col.append(h("div", { class: "reply-meta", text: n }));
    if (m.sources?.length) {
      const links = h("div", { class: "reply-sources" });
      for (const s of m.sources) {
        links.append(h("a", { href: s.url, text: s.title || s.url, onclick: (e: Event) => {
          e.preventDefault();
          actions.openUrl(s.url);
        } }));
      }
      col.append(links);
    }
    if (m.caption) col.append(h("div", { class: "reply-caption", text: m.caption }));
    return h("div", { class: "chat-row" }, col);
  }

  function emptyState(): HTMLElement {
    return h(
      "div",
      { class: "empty-state" },
      h("button", { class: "btn primary", text: "Add a cloud key", onclick: () => actions.openSettingsWindow("chat/keys") }),
      h("button", { class: "btn secondary", text: "Use a local model", onclick: () => { showGuide = true; State.notify(); } }),
      // The first run: Settings → AI and chat opens on Your AI.
      h("button", { class: "btn secondary", text: "Connect Claude", onclick: () => actions.openSettingsWindow("chat/yourai") }),
    );
  }

  /** "Claude needs permission" for the step it is waiting to take, with Allow and Deny: the island's own approval card. */
  function approvalCard(): HTMLElement | null {
    const waiting = link.approval();
    if (!waiting) return null;
    return h(
      "div",
      { class: "chat-row" },
      h(
        "div",
        { class: "chat-approval" },
        h("div", { class: "who", text: "Claude needs permission" }),
        h("div", { class: "code", text: waiting.command || waiting.tool }),
        h("div", { class: "actions" },
          h("button", { class: "btn secondary", text: "Deny", onclick: () => link.decide("deny", waiting.requestId) }),
          h("button", { class: "btn primary", text: "Allow", onclick: () => link.decide("allow", waiting.requestId) })),
      ),
    );
  }

  function guide(): HTMLElement {
    const links = GUIDE_LINKS.map(([name, url]) =>
      h("a", { href: url, text: name, onclick: (e: Event) => { e.preventDefault(); actions.openUrl(url); } }),
    );
    return h(
      "div",
      { class: "chat-note guide" },
      h("span", {}, "Install ", links[0], " or ", links[1], ", start it and download a model, then rescan."),
      smallButton("Rescan", async () => {
        await Bridge.aiDiscover();
        showGuide = false;
        await refreshModel();
      }),
    );
  }

  send.addEventListener("click", () => void submit());
  input.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter") {
      e.preventDefault();
      submit();
    }
    e.stopPropagation(); // Escape closes the island, not the chat
  });

  return {
    el,
    sync() {
      const file = State.droppedFile;
      const wantChip = file?.name ?? "";
      // A waiting picture gets its own chip: Explain this screenshot starts a new chat with it.
      const shot = State.pendingAttachment !== null && isImageName(State.pendingAttachment);
      const held = sending || (State.quickResult?.running ?? false);
      const chipKey = `${wantChip}|${shot}|${held}`;
      if (fileChipSlot.dataset.label !== chipKey) {
        fileChipSlot.dataset.label = chipKey;
        clear(fileChipSlot);
        if (wantChip) fileChipSlot.append(contextChip(wantChip));
        if (shot) fileChipSlot.append(h("button", { class: "chip cm-shot", text: SCREENSHOT_CHIP, disabled: held, onclick: () => void explainScreenshot() }));
      }

      const quick = State.quickResult;
      const quickKey = quick ? `${quick.kind}|${quick.running}|${quick.cut}|${quick.note ?? ""}|${quick.text}` : "";
      if (quickKey !== quickDrawn) {
        quickDrawn = quickKey;
        drawQuick(quick);
      }

      const thinking = State.stateOverride === "thinking";
      const empty = !!resolution?.empty;
      const waiting = link.approval();
      const key = [
        thinking, empty, showGuide, waiting?.requestId ?? "",
        // A note's text can change at the same length (a countdown), so notes key on their text.
        // A local answer's words can change (the ledger moves on only when asked again, but a card is a card): it keys on its lines.
        Hub.sk?.ledger.live.length ? "live" : "",
        ...State.localAnswers.map((a) => `la${a.id}:${a.afterCount}:${a.lines.join("/")}`),
        ...State.chatHistory.map((m) =>
          `${m.id}:${m.role === "note" ? m.content : m.content.length}:${m.status ?? ""}:${m.caption ?? ""}:${m.sources?.length ?? 0}:${m.notices?.length ?? 0}:${m.action?.kind ?? ""}:${(m.steps ?? []).map((s) => s.id + s.state).join(",")}`),
      ].join("|");
      if (key !== renderedKey) {
        renderedKey = key;
        clear(log);
        for (const row of interleave(State.chatHistory, State.localAnswers)) {
          if ("answer" in row) { log.append(...localCard(row.answer)); continue; }
          const m = row.message;
          if (m.role === "assistant" && !m.content && !m.steps?.length && thinking) continue;
          log.append(bubble(m));
        }
        const card = approvalCard();
        if (card) log.append(card);
        if (thinking) log.append(typingDots());
        // The chip of the empty conversation: the question the Sidekick answers on this computer.
        if (Hub.sk && Hub.sk.ledger.live.length > 0 && State.chatHistory.length === 0 && State.localAnswers.length === 0) {
          log.append(h("div", { class: "empty-state" }, h("button", { class: "btn secondary", text: STATUS_CHIP_TEXT, onclick: () => void answerLocally(STATUS_CHIP_TEXT) })));
        }
        if (empty && !showGuide) log.append(emptyState());
        if (showGuide) log.append(guide());
        log.scrollTop = log.scrollHeight;
      }

      picker.style.display = pickerOpen ? "" : "none";
      levelPicker.style.display = levelPickerOpen ? "" : "none";
      // The menu and the Conversations pane take the log's and the bar's place. A reply cancels the menu, and its chip is off during one.
      if (sending) menuOpen = false;
      menu.style.display = menuOpen ? "" : "none";
      listPane.style.display = pane === "list" ? "" : "none";
      log.style.display = pane === "list" ? "none" : "";
      bar.style.display = pane === "list" ? "none" : "";
      menuChipEl.toggleAttribute("disabled", sending);
      newChatItem.toggleAttribute("disabled", sending);
      popOutItem.toggleAttribute("disabled", sending);
      const quickBusy = sending || (State.quickResult?.running ?? false);
      const hasText = input.value.trim() !== "";
      for (const item of [fixItem, rewriteItem, explainItem]) item.toggleAttribute("disabled", quickBusy || !hasText);
      // A reply that ends while the list is open (it cannot start there) would leave the rows' Open off: they are built again.
      if (pane === "list" && drawnSending !== sending) drawList();
      levelChipEl.style.display = usesClaude() ? "" : "none";
      // The level chip takes the right-hand edge, and the model chip sits beside it.
      modelChipEl.style.marginLeft = usesClaude() ? "0" : "";
      levelChipEl.textContent = folderLabel(State.claudeLevel.level, State.claudeLevel.folder);
      levelChipEl.toggleAttribute("disabled", sending);
      send.toggleAttribute("disabled", !sending && (quick?.running ?? false));
      const mode = sending ? "stop" : "send";
      if (send.dataset.mode !== mode) {
        send.dataset.mode = mode;
        send.replaceChildren(svg(sending ? ICONS.stop : ICONS.arrowUp, 11));
        send.title = sending ? "Stop" : "Send";
      }
      input.placeholder = State.chatHistory.length === 0 ? "Ask me anything…" : "Continue…";
      input.disabled = sending;
      // In its own window the chat shows here only the note and the way back.
      const out = State.chatPoppedOut;
      poppedEl.style.display = out ? "" : "none";
      chipRow.style.display = out ? "none" : "";
      if (out) for (const part of [menu, log, listPane, picker, levelPicker, bar]) part.style.display = "none";
      // The autosave line shows only while this chat is the one whose save was refused (a new chat clears it), and not in the pop-out's note-only view.
      unsavedEl.style.display = !out && pane === "chat" && unsavedAt !== null && unsavedAt === State.chatEpoch ? "" : "none";
      // The card belongs to the chat's own view: not in the conversations pane, and not in the island while the chat is in its own window.
      quickEl.style.display = quick && pane === "chat" && !out ? "" : "none";
    },
    focus() {
      input.focus();
      input.select();
      void (async () => {
        // Before a chat's first message: is Claude Code there, and signed in? (Never on a timer.)
        if (State.settings.ai.claudeCodeEnabled && State.chatHistory.length === 0) {
          State.claudeStatus = (await Bridge.claudeStatus()) ?? State.claudeStatus;
        }
        await refreshModel();
      })();
      void Bridge.aiPrewarm(nextFeature());
    },
    refreshModel,
  };
}
