// Claude Code in the chat, the parts that hold logic: which hook payloads belong to a chat, the words on the chips, the
// step rows and the note for a plan limit, and the queue of approvals waiting for a click. No DOM, and no imports besides
// types and `steps.ts`, so the plain-Node check in scripts/check-claude-ui.mjs loads this file as it is. The rules are the
// shared fixtures in tests/fixtures/ai/claude-code/ (hook-routing.json, labels.json, copy.json).

import { stepLabel } from "./steps.ts";

/** `none` is the no-tools level of a quick action (and of an Explain chat until the picker is used): the picker never offers it. */
export type ClaudeLevel = "chat" | "read" | "agent" | "none";

/** What Claude may do in this chat (`claude_set_level` in Rust). Every new chat starts at Chat only. */
export interface ClaudeChatLevel {
  level: ClaudeLevel;
  folder: string | null;
}

/** Who pays for a run, as Claude Code's own first event says. */
export type Payer = "plan" | "api_key" | "unknown";

/** What the last check found of Claude Code (`claude_status` in Rust). `signedIn` is the only state that counts as ready. */
export interface ClaudeStatus {
  state: "notInstalled" | "tooOld" | "signedOut" | "signedIn" | "unknown";
  version: string | null;
  authMethod: string | null;
  shimOnly: boolean;
  needsGit: boolean;
}

/** One step Claude Code takes on its own, shown as a row in the chat. */
export interface ClaudeStep {
  id: string;
  tool: string;
  input: Record<string, string>;
  state: "running" | "done" | "failed" | "stopped";
}

/** Where Anthropic's installer is: NotchMeow links to it and installs nothing. */
export const INSTALL_GUIDE = "https://docs.claude.com/en/docs/claude-code/setup";
export const GIT_FOR_WINDOWS = "https://git-scm.com/downloads/win";

/**
 * Which hook payloads belong to a chat. `live` is the set of session ids NotchMeow chose with --session-id for chats that
 * are still open. Only an exact match of a string `session_id` counts, and a payload from another agent (`nm_agent`) never
 * does. A chat's payload goes to that chat and never creates or touches a pill; everything else is handled as before.
 */
export function routeHook(payload: { session_id?: unknown; nm_agent?: unknown }, live: ReadonlySet<string>): "chat" | "other" {
  if (typeof payload.nm_agent === "string" && payload.nm_agent !== "") return "other";
  const id = payload.session_id;
  return typeof id === "string" && id !== "" && live.has(id) ? "chat" : "other";
}

/**
 * Who pays, in words. What the last run reported wins; before any run, the sign-in method. A cloud account (Bedrock,
 * Vertex) is neither, and an unknown answer never claims "your plan".
 */
export function modelChip(authMethod: string | null, paidBy: Payer | null): string {
  if (authMethod === "third_party") return "Claude";
  if (paidBy === "plan") return "Claude · your plan";
  if (paidBy === "api_key") return "Claude · API key";
  if (authMethod === "claude.ai" || authMethod === "oauth_token") return "Claude · your plan";
  if (authMethod === "api_key" || authMethod === "api_key_helper") return "Claude · API key";
  return "Claude";
}

/** The last part of a path, whichever separator it uses; "/" and "C:" keep their own names. */
export function folderName(folder: string): string {
  const trimmed = folder.replace(/[\\/]+$/, "");
  if (trimmed === "") return folder.slice(0, 1);
  return trimmed.split(/[\\/]/).pop() ?? trimmed;
}

/** "Chat only", "Read-only · notchmeow", "Agent · Mis Proyectos". */
export function levelChip(level: ClaudeLevel, folder: string | null): string {
  const words = { chat: "Chat only", read: "Read-only", agent: "Agent", none: "No tools" }[level];
  if (level === "chat" || level === "none" || !folder) return words;
  return `${words} · ${folderName(folder)}`;
}

/** How Claude Code is signed in, in words: "your Claude plan", "an API key". */
export function signInWords(authMethod: string | null): string {
  switch (authMethod) {
    case "claude.ai": return "your Claude plan";
    case "oauth_token": return "an OAuth token";
    case "api_key": return "an API key";
    case "api_key_helper": return "an API key helper";
    case "third_party": return "a cloud account";
    default: return "its own sign-in";
  }
}

/** A step that never finished (Stop, a crash) ends as stopped: no row stays "running". The others are left alone. */
export function endUnfinished(steps: ClaudeStep[]): ClaudeStep[] {
  return steps.map((s) => (s.state === "running" ? { ...s, state: "stopped" as const } : s));
}

/** "Reads · README.md", with a mark when the step failed or was stopped. */
export function stepRow(step: ClaudeStep): string {
  const line = stepLabel(step.tool, step.input);
  if (step.state === "failed") return `${line} ⚠`;
  if (step.state === "stopped") return `${line} · stopped`;
  return line;
}

/**
 * "Your Claude plan's limit resets at 3:45 pm." in the viewer's time zone and locale; Rust sends only the base words and
 * `resetsAt` (Unix seconds). A recent ICU puts a narrow no-break space before PM: a plain one is used, and PM is lower-cased.
 */
export function planLimitNote(message: string, resetsAt: number | null | undefined, locale?: string, timeZone?: string): string {
  if (resetsAt == null) return message;
  const time = new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit", timeZone })
    .format(new Date(resetsAt * 1000))
    .replace(/[\u202f\u00a0]/g, " ")
    .toLowerCase();
  return `Your Claude plan's limit resets at ${time}.`;
}

/** A step Claude Code is waiting to take: the card in the chat shows the first. Mirrors `ApprovalInfo` in state.ts. */
export interface WaitingApproval {
  requestId: string;
  sessionId: string;
  tool: string;
  command: string;
}

/** Requests wait here in the order they arrived (parallel tool calls ask together); the card shows the first. */
export class ApprovalQueue {
  private items: WaitingApproval[] = [];

  get front(): WaitingApproval | null {
    return this.items[0] ?? null;
  }

  get length(): number {
    return this.items.length;
  }

  push(item: WaitingApproval): void {
    this.items.push(item);
  }

  /** The first request, answered or given up on. */
  popFront(): WaitingApproval | null {
    return this.items.shift() ?? null;
  }

  /** One request by id (its connection closed, or it timed out). */
  remove(requestId: string): WaitingApproval | null {
    const i = this.items.findIndex((x) => x.requestId === requestId);
    return i < 0 ? null : this.items.splice(i, 1)[0];
  }

  /** Every request of one session, or all of them (no argument): Stop, a new conversation, a level change. */
  removeAll(sessionId?: string): WaitingApproval[] {
    const gone = this.items.filter((x) => sessionId === undefined || x.sessionId === sessionId);
    this.items = this.items.filter((x) => !gone.includes(x));
    return gone;
  }
}
