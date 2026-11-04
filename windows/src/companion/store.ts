// The conversation files as the page sees them (sub-project F3a-tauri, docs/COMPANION-CONTRACT.md "Conversation records"). Rust holds the files
// (src-tauri/src/companion_store.rs). The page cleans every record with conversationClean before it saves it, and keeps at most 50 (conversationsKeep).
// The store is a StoreBackend: the app's files through Bridge here, a stand-in in the tests. Pure apart from the backend and the id source.

import { Bridge } from "../core/bridge.ts";
import type { ChatMessage } from "../core/state.ts";
import { conversationClean, conversationsKeep, titleOf } from "./core.ts";
import type { Conversation, StoredMessage } from "./core.ts";

/** A saved conversation's head, as the list shows it (Rust's `Head`). */
export interface Head {
  id: string;
  title: string;
  pinned: boolean;
  updatedAt: number;
}

/** Where the conversations live: the app's files through Bridge, or a stand-in in the tests. */
export interface StoreBackend {
  list(): Promise<Head[]>;
  load(id: string): Promise<unknown>;
  save(rec: Conversation): Promise<boolean>;
  remove(id: string): Promise<boolean>;
  removeAll(): Promise<boolean>;
}

/** The list's heads with each title through titleOf (the contract's rule), so the pane never shows a title the rule would cut. */
export function cleanHeads(heads: readonly Head[]): Head[] {
  return heads.map((h) => ({ ...h, title: titleOf(h.title) }));
}

/** The app's files, through the five companion commands. Outside Tauri there are none. */
export const bridgeStore: StoreBackend = {
  list: async () => cleanHeads(await Bridge.companionList()),
  load: (id) => Bridge.companionLoad(id),
  save: (rec) => Bridge.companionSave(rec),
  remove: (id) => Bridge.companionDelete(id),
  removeAll: () => Bridge.companionDeleteAll(),
};

/** A new conversation id: a random UUID in lower case, which the core's id rule accepts. */
export function newId(): string {
  return crypto.randomUUID();
}

/** The last part of a path or a name (`C:\dev\inbox\a.png` is `a.png`): a conversation keeps names, never the folders they sit in. */
const lastPart = (path: string): string => path.split(/[\\/]/).pop() ?? path;

/**
 * A conversation's record from the chat's messages: user and assistant messages only (a note is never kept), each with its caption and its file names. The title is
 * the given one, else the first user message's. Cleaned by conversationClean; null when the record does not clean (its id is not the contract's).
 */
export function recordOf(c: { id: string; createdAt: number; pinned: boolean; title?: string }, history: readonly ChatMessage[], now: number): Conversation | null {
  const kept = history.filter((m) => m.role === "user" || m.role === "assistant");
  const messages: StoredMessage[] = kept.map((m) => ({
    role: m.role === "user" ? "user" : "assistant",
    text: m.content,
    caption: m.caption ?? "",
    files: (m.attachments ?? []).map(lastPart),
  }));
  const firstUser = kept.find((m) => m.role === "user");
  const title = c.title ?? titleOf(firstUser?.content ?? "");
  return conversationClean({ version: 1, id: c.id, title, pinned: c.pinned, createdAt: c.createdAt, updatedAt: now, messages });
}

/** A saved conversation's messages back as the chat's, with the ids `nextId` gives. A file stays a name: the chat never gets a file's body back. */
export function messagesOf(rec: Conversation, nextId: () => number): ChatMessage[] {
  return rec.messages.map((m) => ({
    id: nextId(),
    role: m.role,
    content: m.text,
    ...(m.caption ? { caption: m.caption } : {}),
    ...(m.files.length ? { attachments: m.files } : {}),
  }));
}

/** Saves a conversation, then keeps the 50 the core allows: the rest (pinned first kept, the oldest unpinned first removed). False, and nothing removed, when the save is refused. */
export async function saveAndKeep(store: StoreBackend, rec: Conversation): Promise<boolean> {
  if (!(await store.save(rec))) return false;
  const { evict } = conversationsKeep(await store.list());
  for (const id of evict) await store.remove(id);
  return true;
}

/**
 * A saved conversation as the page opens it. The stored value is judged by conversationClean like any record the page builds: a value that does not clean, or whose
 * cleaned id is not the one asked for, is not opened (null). The files are data; nothing from them is trusted until it has been cleaned here.
 */
export async function loadRecord(store: StoreBackend, id: string): Promise<Conversation | null> {
  const rec = conversationClean(await store.load(id));
  return rec !== null && rec.id === id ? rec : null;
}
