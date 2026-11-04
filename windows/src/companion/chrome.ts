// The companion's words: the level chip, the level rows, the menu and the pane. They follow the Mac (CompanionChrome.swift); Task 12 pins them.
import { folderName, modelChip, type ClaudeLevel, type Payer } from "../core/claude.ts";
import type { Resolution } from "../core/bridge.ts";

/** The level chip's words: "No folder", "Reads · notchmeow", "Works in · site", or the bare word with no folder. */
export function folderLabel(level: ClaudeLevel, folder: string | null): string {
  if (level === "chat") return "No folder";
  if (level === "none") return "No tools";
  const word = level === "read" ? "Reads" : "Works in";
  return folder ? `${word} · ${folderName(folder)}` : word;
}

/** The three level rows, in the order Chat only, Read, Agent. */
export const FOLDER_ROWS = ["No folder", "Read a folder…", "Work in a folder…"] as const;
export const FOLDER_TITLE = "The folder Claude may use in this chat";
export const POPPED_OUT_NOTE = "The chat is in its own window.";
export const BRING_BACK = "Bring it back";
/** The pop-out window has no Sidekick, so it cannot answer "What's Claude doing?" from the ledger; it never sends that question to a model. */
export const STATUS_IN_ISLAND_NOTE = "Ask this in the island — the window can't see your sessions.";
export const QUICK_TITLES = { fix: "Fixed", rewrite: "Rewritten" } as const;
export const CUT_NOTE = "Cut to the first 8,000 characters.";
export const SCREENSHOT_CHIP = "Explain this screenshot";
export const QUICK_COPY = "Copy";
export const QUICK_TOO_LONG = "Too long to copy.";
export const QUICK_CLOSE = "Close";
/** A quick action with no brain to answer it: the Settings page's words for the same state (settings/ai.ts). */
export const NO_MODEL_NOTE = "No model yet: add a cloud key or start a local model.";
/** The one line under the chat while its last autosave was refused. Cleared by the next save that works, or by a new chat. */
export const UNSAVED_NOTE = "This chat isn't saved.";
/** A saved conversation that could not be opened: the chat says so, in the chat or the island, and never starts quietly. */
export const OPEN_FAILED_NOTE = "That conversation couldn't be opened.";
/** The Conversations pane's notes for a refused change (the pane keeps its rows and shows one line). */
export const LIST_NOTES = {
  deleteOne: "Couldn't delete that one.",
  deleteAll: "Couldn't delete the conversations.",
  pin: "Couldn't pin it.",
  rename: "Couldn't rename it.",
  pinFull: "Unpin one to pin another.",
} as const;

export const MENU = {
  newChat: "New chat",
  conversations: "Conversations",
  popOut: "Pop out",
  fix: "Fix",
  rewrite: "Rewrite",
  explain: "Explain",
} as const;

/** The Conversations pane's own words. (Four of its lines stay literal in chat.ts: a Task 6 pin reads them there.) */
export const PANE = {
  back: "Back",
  pin: "Pin",
  unpin: "Unpin",
  pinned: "pinned",
  rename: "Rename",
  delete: "Delete",
  deleteAll: "Delete all",
  save: "Save",
  cancel: "Cancel",
} as const;

/** The model chip's words: "No model yet", Claude Code's own words, or the model's name ("Auto · " in front when Auto is on). Shared by the chat's chip and the Settings line. */
export function chipLabel(r: Resolution | null, authMethod: string | null, paidBy: Payer | null): string {
  if (!r || r.empty) return "No model yet";
  // Who pays is what Claude Code reported, never a guess.
  if (r.provider === "claudeCode") return modelChip(authMethod, paidBy);
  const name = r.modelName ?? r.provider ?? "";
  return r.auto ? `Auto · ${name}` : name;
}

/** The line under the brain's name: what leaves the machine with each message. */
export function sentTo(brain: string): string {
  return `This is sent with your messages to ${brain}.`;
}
