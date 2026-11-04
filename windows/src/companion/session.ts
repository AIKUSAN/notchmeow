// The chat's saved conversations (sub-project F3a-tauri, Task 6): a new chat, opening one, saving the open one, rename, pin and delete. The files are
// the store's (companion/store.ts); the chat's words are the chat view's (views/chat.ts). Nothing here logs, shows or keeps a message's text outside
// the conversation records, and nothing runs on a timer.

import { Bridge } from "../core/bridge.ts";
import { forgetDrop } from "../core/feature.ts";
import { State } from "../core/state.ts";
import { CONVERSATIONS_MAX, titleOf } from "./core.ts";
import type { ChatLink } from "./link.ts";
import { loadRecord, messagesOf, newId, recordOf, saveAndKeep } from "./store.ts";
import type { StoreBackend } from "./store.ts";

/** What the chat tells Rust: a new conversation (`chat_reset`) and the words of an opened one (`ai_load_turns`). Both are sync commands, so they arrive in order. */
export interface ChatBackend {
  reset(): void;
  loadTurns(t: { role: "user" | "assistant"; text: string }[]): void;
}

export const bridgeChat: ChatBackend = {
  reset: () => void Bridge.chatReset(),
  loadTurns: (t) => void Bridge.aiLoadTurns(t),
};

/** One counter for every message in the chat, restored ones included, so no two messages share an id. */
let lastMessageId = 0;
export function nextMessageId(): number {
  return ++lastMessageId;
}

/** The pins at most: one short of the 50 kept, so a pin is never the one the cap evicts. */
const PINS_MAX = CONVERSATIONS_MAX - 1;

/** How a pin attempt ended: pinned or unpinned, refused at the cap, or not written. */
export type PinResult = "pinned" | "unpinned" | "full" | "failed";

/**
 * A new chat: the history, the approvals and the Claude session go, and the chat is not saved yet. Whatever Claude Code was waiting to do is refused.
 * The dropped file goes too (its chip, its context and the file waiting for the next send). The island's drop never calls this, so a drop's file is not lost here.
 * The order is the island's own drop reset: release, then reset Claude, then tell Rust.
 */
export function startNewChat(link: ChatLink, chat: ChatBackend): void {
  State.chatHistory = [];
  State.localAnswers = [];
  forgetDrop(State);
  State.chatEpoch++;
  State.chatId = null;
  State.chatTitle = null;
  State.chatPinned = false;
  State.chatCreatedAt = 0;
  link.release();
  State.resetClaude();
  chat.reset();
}

/** A line the chat shows and keeps to itself: a note is never sent to a brain and never saved (recordOf keeps only the user's and the reply's messages). */
export function noteInChat(text: string): void {
  State.chatHistory.push({ id: nextMessageId(), role: "note", content: text, action: null });
}

/**
 * Saves the open conversation (nothing when it has no user message). The first save gives it an id and a creation time. The id is made before any await,
 * and the record is built from a snapshot, so a new chat started during the save is never written over.
 */
export async function saveCurrent(store: StoreBackend, now: number): Promise<boolean> {
  if (!State.chatHistory.some((m) => m.role === "user")) return false;
  if (State.chatId === null) {
    State.chatId = newId();
    State.chatCreatedAt = now;
    // A title or a pin left by the conversation a drop closed is not this one's.
    State.chatTitle = null;
    State.chatPinned = false;
  }
  const rec = recordOf(
    { id: State.chatId, createdAt: State.chatCreatedAt, pinned: State.chatPinned, title: State.chatTitle ?? undefined },
    State.chatHistory,
    now,
  );
  return rec !== null && (await saveAndKeep(store, rec));
}

/**
 * Opens a saved conversation as the chat: the record is read through loadRecord (cleaned, and its id checked). A record that does not clean is not
 * opened, and nothing changes. The chat must not be in the middle of a reply: Rust's `ai_load_turns` cancels one.
 */
export async function openConversation(store: StoreBackend, id: string, link: ChatLink, chat: ChatBackend): Promise<boolean> {
  const rec = await loadRecord(store, id);
  if (rec === null) return false;
  startNewChat(link, chat);
  State.chatId = rec.id;
  State.chatTitle = rec.title;
  State.chatPinned = rec.pinned;
  State.chatCreatedAt = rec.createdAt;
  State.chatHistory = messagesOf(rec, nextMessageId);
  // Only the words go to Rust: a restored file stays a name here, and is never sent as a path.
  chat.loadTurns(rec.messages.map((m) => ({ role: m.role, text: m.text })));
  return true;
}

/**
 * Renames a conversation. The open one keeps its title with the chat and is saved. Another is changed in its file and keeps its place in the list (its
 * time is not touched).
 */
export async function rename(store: StoreBackend, id: string, title: string, now: number): Promise<boolean> {
  const t = titleOf(title);
  if (id === State.chatId) {
    State.chatTitle = t;
    return saveCurrent(store, now);
  }
  const rec = await loadRecord(store, id);
  return rec !== null && (await saveAndKeep(store, { ...rec, title: t }));
}

/**
 * Pins or unpins a conversation. A pin past the cap is refused ("full"), an unpin is always allowed. The open one's pin is saved with the chat; another's
 * is changed in its file and keeps its time, so it keeps its place.
 */
export async function togglePin(store: StoreBackend, id: string, now: number): Promise<PinResult> {
  const heads = await store.list();
  const open = id === State.chatId;
  const was = open ? State.chatPinned : heads.some((h) => h.id === id && h.pinned);
  const want = !was;
  if (want && heads.filter((h) => h.pinned && h.id !== id).length >= PINS_MAX) return "full";
  let ok: boolean;
  if (open) {
    State.chatPinned = want;
    ok = await saveCurrent(store, now);
    if (!ok && State.chatId === id) State.chatPinned = was;
  } else {
    const rec = await loadRecord(store, id);
    ok = rec !== null && (await saveAndKeep(store, { ...rec, pinned: want }));
  }
  return ok ? (want ? "pinned" : "unpinned") : "failed";
}

/** Deletes one conversation's file. When it is the open one, the chat starts again: its next reply must not save it back under the same id. */
export async function removeOne(store: StoreBackend, id: string, link: ChatLink, chat: ChatBackend): Promise<boolean> {
  if (!(await store.remove(id))) return false;
  if (id === State.chatId) startNewChat(link, chat);
  return true;
}

/** Deletes every conversation. The chat starts again only when the open conversation was one of them; an open chat not saved yet stays. */
export async function removeAll(store: StoreBackend, link: ChatLink, chat: ChatBackend): Promise<boolean> {
  const heads = await store.list();
  const hadOpen = State.chatId !== null && heads.some((h) => h.id === State.chatId);
  const ok = await store.removeAll();
  if (ok && hadOpen) startNewChat(link, chat);
  return ok;
}

/**
 * Rust tells every window when the conversations were all deleted (`companion-deleted-all`: from Settings, or from this chat's own Delete all). An open chat with a
 * saved id forgets it, so its next reply starts a new conversation and the rows on screen are never written back under the old id. Idempotent: a chat with no id
 * (never saved, or already reset) is left alone. Returns whether it reset anything.
 */
export function forgetDeletedAll(link: ChatLink, chat: ChatBackend): boolean {
  if (State.chatId === null) return false;
  startNewChat(link, chat);
  return true;
}
