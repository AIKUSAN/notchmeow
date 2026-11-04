// The AI rows of Settings → AI and chat on Windows and Linux: which rows show and in what order, their words and chips, what Make main does, and which row is the
// chat's main choice. Port of NotchBuddy/Sources/App/SettingsAI.swift (there, the Apple row and the GitHub-build gate are Mac-only). Pure: no DOM, no storage, no clock.
// Tests: windows/scripts/settings-tests (check:settings); drift.test.mjs holds the words to SettingsAI.swift.

import { keyChip, UNREADABLE_ROW_CHIP } from "./status.ts";
import type { ModelChoice } from "../core/state.ts";
import type { AiServer } from "../core/bridge.ts";
import type { ClaudeStatus } from "../core/claude.ts";
import type { AiSettings } from "../core/state.ts";

export type KeyProvider = "anthropic" | "google" | "openai";
export type Row = { kind: "claudePlan" } | { kind: "openAIPlan" } | { kind: "key"; provider: KeyProvider } | { kind: "server"; id: string };
/** A model server as the rows read it: `id` is AiServer.provider. */
export interface ServerIn { id: string; name: string; network: boolean; models: string[]; status?: string }
export interface AiInput {
  claudeState: ClaudeStatus["state"] | null;
  claudeEnabled: boolean;
  claudeModel: string;
  /** The providers whose key is stored. */
  keys: readonly KeyProvider[];
  /** The providers whose key the store could not be read for (not ready; never "No key yet"). Optional, default none. */
  unreadable?: readonly KeyProvider[];
  cloudModel: Record<string, string>;
  servers: readonly ServerIn[];
  memory: Record<string, string>;
  /** Each cloud provider's model ids in the window's list, in order (Rust's Auto reads them when a provider has no catalog default). Optional, default none. */
  cloudIds?: Record<string, readonly string[]>;
}
export type Choice = { provider: string; model: string };
export type MakeMain = { kind: "set"; choice: Choice } | { kind: "menu"; choices: Choice[] } | { kind: "unavailable"; reason: string };

export const PLAN_LINE = "Runs your own installed app, signed in by you. NotchMeow never sees your login.";
export const COMING = "Coming with the new chat";
export const KEY_PROVIDERS: readonly KeyProvider[] = ["anthropic", "google", "openai"];

const KEY_TITLES: Record<KeyProvider, string> = { anthropic: "Anthropic API key", google: "Google AI API key", openai: "OpenAI API key" };
/** The ids a server may not take: a server with one of them would look like a cloud row for Make main. */
const RESERVED_IDS: readonly string[] = ["claudeCode", ...KEY_PROVIDERS];
const GET_LINKS = new Map<string, string>([
  ["ollama", "https://ollama.com/download"], ["lmstudio", "https://lmstudio.ai"], ["jan", "https://jan.ai"], ["llamacpp", "https://github.com/ggml-org/llama.cpp"],
]);

const serverOf = (i: AiInput, id: string): ServerIn | undefined => i.servers.find((s) => s.id === id);
const hasKey = (i: AiInput, r: { provider: KeyProvider }): boolean => i.keys.includes(r.provider);
/** The key the store could not be read for (never "No key yet" for it). */
export const isUnreadable = (i: AiInput, r: { provider: KeyProvider }): boolean => (i.unreadable ?? []).includes(r.provider);

export function rowKey(r: Row): string {
  return r.kind === "key" ? `key:${r.provider}` : r.kind === "server" ? `server:${r.id}` : r.kind;
}

/** The plan rows, then each key, then each server that has at least one model, in input order. */
export function rows(i: AiInput): Row[] {
  return [
    { kind: "claudePlan" },
    { kind: "openAIPlan" },
    ...KEY_PROVIDERS.map((provider): Row => ({ kind: "key", provider })),
    ...i.servers.filter((s) => s.models.length > 0).map((s): Row => ({ kind: "server", id: s.id })),
  ];
}

export function title(r: Row, i: AiInput): string {
  switch (r.kind) {
    case "claudePlan": return "Use my Claude plan";
    case "openAIPlan": return "Use my OpenAI plan";
    case "key": return KEY_TITLES[r.provider];
    case "server": return serverOf(i, r.id)?.name ?? "";
  }
}

export function line(r: Row, i: AiInput): string {
  switch (r.kind) {
    case "claudePlan":
    case "openAIPlan": return PLAN_LINE;
    case "key": return "Your own key, saved on the Keys tab.";
    case "server": return serverOf(i, r.id)?.network ? "A model server on your network." : "A model server on this computer.";
  }
}

export function chip(r: Row, i: AiInput): string {
  switch (r.kind) {
    case "claudePlan":
      switch (i.claudeState) {
        case "signedIn": return i.claudeEnabled ? "Ready" : "Off";
        case "signedOut": return "Not signed in";
        case "notInstalled": return "Not installed";
        case "tooOld": return "Needs update";
        default: return "Not ready";
      }
    case "openAIPlan": return COMING;
    case "key": return isUnreadable(i, r) ? UNREADABLE_ROW_CHIP : keyChip(hasKey(i, r));
    case "server": return serverChip("running", serverOf(i, r.id)?.models.length ?? 0);
  }
}

export function serverChip(status: AiServer["status"], modelCount: number): string {
  switch (status) {
    case "running":
      if (modelCount === 0) return "Running, no models yet";
      return modelCount === 1 ? "Running, 1 model" : `Running, ${modelCount} models`;
    case "off": return "Server off";
    case "notInstalled": return "Not installed";
    case "outdated": return "Update needed";
  }
}

/** What the row's "Make main" does: set the chat's choice, offer a menu (a server with several models), or say why it cannot. */
export function makeMain(r: Row, i: AiInput): MakeMain {
  switch (r.kind) {
    case "claudePlan":
      if (i.claudeState === "signedIn" && i.claudeEnabled) return { kind: "set", choice: { provider: "claudeCode", model: i.claudeModel } };
      return { kind: "unavailable", reason: "Connect your Claude plan first." };
    case "openAIPlan":
      return { kind: "unavailable", reason: "Coming with the new chat." };
    case "key": {
      if (isUnreadable(i, r)) return { kind: "unavailable", reason: `${UNREADABLE_ROW_CHIP}.` };
      if (!hasKey(i, r)) return { kind: "unavailable", reason: "Add a key on the Keys tab first." };
      const model = i.cloudModel[r.provider];
      if (!model) return { kind: "unavailable", reason: "Pick a model for it in the chat first." };
      return { kind: "set", choice: { provider: r.provider, model } };
    }
    case "server": {
      const server = serverOf(i, r.id);
      if (!server || server.models.length === 0) return { kind: "unavailable", reason: "Start the server and load a model first." };
      if (server.models.length === 1) return { kind: "set", choice: { provider: server.id, model: server.models[0] } };
      // The model used last comes first; the rest keep the server's order.
      const remembered = i.memory[server.id];
      const ordered = remembered !== undefined && server.models.includes(remembered)
        ? [remembered, ...server.models.filter((m) => m !== remembered)]
        : server.models;
      return { kind: "menu", choices: ordered.map((model) => ({ provider: server.id, model })) };
    }
  }
}

/** The line under a row. A key row with no key has none: its chip and its Add a key button say it. */
export function helpLine(r: Row, i: AiInput): string | null {
  if (r.kind === "key" && (!hasKey(i, r) || isUnreadable(i, r))) return null;
  return line(r, i);
}

/** Why a row cannot be made main, as help text under it. None when the chip already says the same, or for a key with no key. */
export function reasonLine(r: Row, i: AiInput): string | null {
  if (r.kind === "key" && (!hasKey(i, r) || isUnreadable(i, r))) return null;
  const m = makeMain(r, i);
  if (m.kind !== "unavailable") return null;
  return m.reason === `${chip(r, i)}.` ? null : m.reason;
}

/** Only an explicit Chat choice is main: Auto has no main row. The OpenAI plan is never main. */
export function isMain(r: Row, chat: ModelChoice): boolean {
  if (chat === "auto") return false;
  switch (r.kind) {
    case "claudePlan": return chat.provider === "claudeCode";
    case "openAIPlan": return false;
    case "key": return chat.provider === r.provider;
    case "server": return !RESERVED_IDS.includes(r.id) && chat.provider === r.id;
  }
}

/** Where to get a local server; null for the cloud providers and anything else. */
export function getLink(provider: string): string | null {
  return GET_LINKS.get(provider) ?? null;
}

/** "Stop using it": Claude off, the preference moved off Claude, and a chat that was set to Claude goes back to Auto (Off and Main on one row would contradict). */
export function afterStopClaude(ai: AiSettings): AiSettings {
  const chat = ai.chat !== "auto" && ai.chat.provider === "claudeCode" ? "auto" : ai.chat;
  return { ...ai, claudeCodeEnabled: false, preferredCloud: ai.preferredCloud === "claudeCode" ? "anthropic" : ai.preferredCloud, chat };
}

/** "Use my Claude plan": Claude on, Claude first, and the chat on Auto. */
export function afterUseClaude(ai: AiSettings): AiSettings {
  return { ...ai, claudeCodeEnabled: true, preferredCloud: "claudeCode", chat: "auto" };
}

/** What a Your AI select's answer depends on, as Rust's resolve reads it: the choices, the keys stored and unreadable, Claude Code's state, the servers with their status, and each
 * cloud provider's model list (Auto's default for a provider with no catalog default). A sync whose signature is the same as the last one asks the backend nothing again. */
export function resolveSignature(ai: AiSettings, input: AiInput): string {
  return JSON.stringify({
    ai,
    keys: input.keys,
    unreadable: input.unreadable ?? [],
    claude: input.claudeState,
    servers: input.servers,
    lists: input.cloudIds ?? {},
  });
}
