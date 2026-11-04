// What the island's "open this agent's app" actions do for a Claude Code session from the Claude desktop app (the relay's `claude-desktop` tag). Such a session belongs to the
// Claude Code pill (`integration_claude`), and its host is the Claude app: State.claudeAppHost says whether the pill's last session runs there. The Mac opens that app by
// its bundle ID (AgentTarget.swift) and labels the finished card's button "Open Claude". Here the app can be started on Windows only: Anthropic ships no Claude desktop app for
// Linux, so there the pill has nothing to open and its buttons are not shown. Pure, so the plain-Node checks can load it.

/** The relay's tag for a session from the Claude desktop app (windows/hook/src/agents.rs). It says where the session runs; the session is Claude Code's. */
export const CLAUDE_DESKTOP_TAG = "claude-desktop";

/** Whether a hook event's `nm_agent` says the session runs in the Claude desktop app. */
export function isClaudeDesktopTag(tag: string | null | undefined): boolean {
  return tag === CLAUDE_DESKTOP_TAG;
}

/**
 * Where the ↗ button of the focused pill goes: "claude-app" (start the Claude desktop app), "vscode" (the project in VS Code), "none" (nothing to open here),
 * "other" (the integrations' own links). `claudeAppHost` is whether the Claude Code pill's session runs in the Claude app (State.claudeAppHost).
 */
export function openRoute(pillId: string | null | undefined, claudeApp: boolean, claudeAppHost: boolean): "claude-app" | "vscode" | "none" | "other" {
  if (pillId === "integration_claude" && claudeAppHost) return claudeApp ? "claude-app" : "none";
  if (pillId === "integration_claude") return "vscode";
  return "other";
}

/** The primary button of the finished card and of a Sidekick nudge about `pillId`: its label and what it starts, or null when there is no such button (Linux, for a session from the Claude app). */
export function finishedAction(pillId: string | null | undefined, claudeApp: boolean, claudeAppHost: boolean): { label: string; kind: "claude-app" | "terminal" } | null {
  if (pillId === "integration_claude" && claudeAppHost) return claudeApp ? { label: "Open Claude", kind: "claude-app" } : null;
  return { label: "Open terminal", kind: "terminal" };
}
