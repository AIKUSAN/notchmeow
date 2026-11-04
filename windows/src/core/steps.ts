// The words of a step row and of the approval card, moved out of island/hooks.ts unchanged so the chat's step rows and the
// island's own read the same way. No imports, so the plain-Node check in scripts/check-claude-ui.mjs can load this file
// as it is.

export function lastPathComponent(p: string): string {
  // A loop, not /[\\/]+$/: that regex is quadratic on a long run of separators before a name (a 60,000-slash path took seconds).
  let end = p.length;
  while (end > 0 && (p[end - 1] === "\\" || p[end - 1] === "/")) end--;
  const cleaned = p.slice(0, end);
  const idx = Math.max(cleaned.lastIndexOf("\\"), cleaned.lastIndexOf("/"));
  return idx >= 0 ? cleaned.slice(idx + 1) : cleaned;
}

/** stepLabel() — same labels as the macOS app. */
const TOOL_LABELS: Record<string, string> = {
  Bash: "Runs",
  Read: "Reads",
  Write: "Writes",
  Edit: "Edits",
  Glob: "Finds",
  Grep: "Searches",
  WebSearch: "Web search",
  WebFetch: "Fetches",
  TodoWrite: "Tasks",
  Task: "Agent",
  LS: "Lists",
  MultiEdit: "Edits",
  NotebookEdit: "Notebook",
  PowerShell: "Runs",
};

export function stepLabel(tool: string, input: Record<string, unknown>): string {
  // An own key only: "constructor" or "__proto__" must show as the tool's own name, never an inherited value.
  const label = Object.hasOwn(TOOL_LABELS, tool) ? TOOL_LABELS[tool] : tool;
  const str = (k: string) => (typeof input[k] === "string" ? (input[k] as string) : null);
  const cmd = str("command");
  if (cmd) return `${label} · ${cmd.slice(0, 40)}`;
  const path = str("path");
  if (path) return `${label} · ${lastPathComponent(path)}`;
  const file = str("file_path");
  if (file) return `${label} · ${lastPathComponent(file)}`;
  const query = str("query");
  if (query) return `${label} · ${query.slice(0, 40)}`;
  return label;
}

/** The step's verb alone: TOOL_LABELS' own value for the tool, else null. Reads no input (the focus note's "Waiting in <host>: <verb>"). */
export function stepVerb(tool: string): string | null {
  return Object.hasOwn(TOOL_LABELS, tool) ? TOOL_LABELS[tool] : null;
}

/**
 * What the Allow button actually authorises. Approving "Write" tells you nothing
 * — approving `Write · C:\…\.env` tells you everything, and the difference is
 * the whole point of approving from the island rather than blind.
 *
 * Ordered by how specific the field is, so an unfamiliar tool still shows
 * whatever identifying string it carries instead of falling back to its name.
 */
const APPROVAL_FIELDS = [
  "command", // Bash, PowerShell
  "file_path", // Write, Edit, MultiEdit, NotebookEdit
  "path", // Read, LS
  "url", // WebFetch
  "query", // WebSearch
  "pattern", // Glob, Grep
  "prompt", // Task
] as const;

export function approvalTarget(tool: string, input: Record<string, unknown>): string {
  for (const field of APPROVAL_FIELDS) {
    const value = input[field];
    if (typeof value === "string" && value.trim()) {
      return `${tool} · ${value.trim()}`;
    }
  }
  return tool;
}
