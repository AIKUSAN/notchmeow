// The chat window's side of the pop-out (sub-project F3a-tauri, Task 9). The island's page and the window's page talk through Rust's `chat_relay`. A relay message is DATA:
// each page checks the shape of every message before it acts, keeps only the fields it knows, and never logs one. The island honours the window's messages only while
// the chat is popped out. This file is pure apart from `State` and imports nothing of the island's hooks, so the plain-Node checks can load it.

import type { WaitingApproval } from "../core/claude.ts";
import { State } from "../core/state.ts";
import { RIGHT_NOW_MAX, conversationClean } from "./core.ts";
import type { ChatLink } from "./link.ts";
import type { TurnContext } from "./turn.ts";

/** What the island pushes the window: the turn context and the approval waiting in the chat (Agent level), if any. */
export interface ToWindow { kind: "context"; context: TurnContext; approval: WaitingApproval | null }
/** What the window tells the island. `decide` is a click of Allow or Deny; the island still checks that the request is the one it has waiting. */
export type ToIsland =
  | { kind: "decide"; decision: "allow" | "deny"; requestId: string }
  | { kind: "release"; sessionId: string | undefined }
  | { kind: "session"; id: string; retired: string | null }
  | { kind: "forget"; id: string }
  | { kind: "current"; id: string };

/** The longest request, session or step text a message may carry: far above any real one, so a bigger one is hostile or broken, not cut. */
const ID_MAX = 200;
const COMMAND_MAX = 4000;
const MOOD_MAX = 40;

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const text = (v: unknown, max: number): v is string => typeof v === "string" && v.length <= max;
const word = (v: unknown): v is string => text(v, ID_MAX) && v !== "";

/** The contract's conversation-id rule, asked of the core (the app carries no copy of it). */
export function isConversationId(v: unknown): v is string {
  return typeof v === "string" && conversationClean({ id: v }) !== null;
}

/** A message the island sent, checked and rebuilt from its known fields; null when it is not one. */
export function checkToWindow(raw: unknown): ToWindow | null {
  if (!isObj(raw) || raw.kind !== "context" || !isObj(raw.context)) return null;
  const c = raw.context;
  if (!text(c.rightNow, RIGHT_NOW_MAX * 4) || typeof c.quiet !== "boolean" || !text(c.mood, MOOD_MAX)) return null;
  // An approval that is not a clean one (an empty id from a hook, a command far too long) is dropped alone: the context is still good.
  let approval: WaitingApproval | null = null;
  const a = raw.approval;
  if (isObj(a) && word(a.requestId) && word(a.sessionId) && text(a.tool, ID_MAX) && text(a.command, COMMAND_MAX)) {
    approval = { requestId: a.requestId, sessionId: a.sessionId, tool: a.tool, command: a.command };
  }
  return { kind: "context", context: { rightNow: c.rightNow, quiet: c.quiet, mood: c.mood }, approval };
}

/** A message the window sent, checked and rebuilt; null when it is not one. */
export function checkToIsland(raw: unknown): ToIsland | null {
  if (!isObj(raw)) return null;
  switch (raw.kind) {
    case "decide":
      return (raw.decision === "allow" || raw.decision === "deny") && word(raw.requestId) ? { kind: "decide", decision: raw.decision, requestId: raw.requestId } : null;
    case "release":
      return raw.sessionId === undefined || raw.sessionId === null ? { kind: "release", sessionId: undefined } : word(raw.sessionId) ? { kind: "release", sessionId: raw.sessionId } : null;
    case "session":
      return word(raw.id) && (raw.retired === null || word(raw.retired)) ? { kind: "session", id: raw.id, retired: raw.retired } : null;
    case "forget":
      return word(raw.id) ? { kind: "forget", id: raw.id } : null;
    case "current":
      return isConversationId(raw.id) ? { kind: "current", id: raw.id } : null;
    default:
      return null;
  }
}

/**
 * The island acts on a message of the window: its Allow or Deny (the island's link refuses any request that is not the one waiting), the window's Claude sessions, and the id of
 * the conversation the window is in. Only while the chat is popped out; anything else, and anything malformed, is dropped.
 */
export function applyToIsland(raw: unknown, link: ChatLink): void {
  if (!State.chatPoppedOut) return;
  const m = checkToIsland(raw);
  if (m === null) return;
  switch (m.kind) {
    case "decide": link.decide(m.decision, m.requestId); break;
    case "release": link.release(m.sessionId); break;
    case "session": link.session(m.id, m.retired); break;
    case "forget": link.forget(m.id); break;
    case "current": State.chatId = m.id; break;
  }
}

/** The window's link: the last context the island pushed (`take`), and the window's answers sent back to the island. */
export function windowLink(send: (msg: unknown) => void): ChatLink & { take(msg: unknown): void } {
  let context: TurnContext = { rightNow: "", quiet: false, mood: "idle" };
  let approval: WaitingApproval | null = null;
  return {
    context: () => context,
    approval: () => approval,
    decide: (decision, requestId) => send({ kind: "decide", decision, requestId }),
    release: (sessionId) => send({ kind: "release", sessionId }),
    session: (id, retired) => send({ kind: "session", id, retired }),
    forget: (id) => send({ kind: "forget", id }),
    take(msg) {
      const m = checkToWindow(msg);
      if (m === null) return;
      context = m.context;
      approval = m.approval;
    },
  };
}
