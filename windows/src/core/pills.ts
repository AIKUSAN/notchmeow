// The colours of the agent pills. The Mac's PillCatalog (NotchBuddy/Sources/App/PillCatalog.swift) is the reference: a collar is drawn from a
// task's colour, so the same agent must have the same colour on both apps. Pill IDs are frozen contract values: `agent_<tag>` for the tag a
// relay puts in `nm_agent` (windows/hook/src/agents.rs). No imports, so the plain-Node checks can load it.

/** The pills of the two agents that have a relay tag (`--agent gemini`, `--agent antigravity`). */
export const AGENT_PILL_COLORS: Readonly<Record<string, string>> = {
  agent_gemini: "#8AB4F8",
  agent_antigravity: "#E879F9",
  // Claude Code sessions from the Claude desktop app (the relay tags them `claude-desktop`); the Mac's PillCatalog has the same colour.
  "agent_claude-desktop": "#E3A857",
};

/** What any other tagged agent gets: a stable pick by name, as before the collar. */
const FALLBACK_COLORS = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"];

/** The names the Mac's PillCatalog gives the agents. Any other tagged agent is its tag, capitalised. */
const AGENT_NAMES: Readonly<Record<string, string>> = { claude: "Claude Code", gemini: "Gemini CLI", antigravity: "Antigravity", codex: "Codex", cursor: "Cursor", "claude-desktop": "Claude App" };

/** The name an agent's pill is created with: its tag, as it always was, except Claude Desktop, whose pill is labelled for a person. */
export function agentPillName(tag: string): string {
  return tag === "claude-desktop" ? AGENT_NAMES[tag] : tag;
}

/** The colour of the pill for `nm_agent` = `name`: its catalogue colour, else a stable hash of the name. */
export function agentColor(name: string): string {
  const id = `agent_${name}`;
  if (Object.hasOwn(AGENT_PILL_COLORS, id)) return AGENT_PILL_COLORS[id];
  let h = 0;
  for (let i = 0; i < name.length; i++) {
    h = (Math.imul(31, h) + name.charCodeAt(i)) | 0;
  }
  return FALLBACK_COLORS[Math.abs(h) % FALLBACK_COLORS.length];
}

/**
 * The name of an agent pill for a person (Settings → Cat → Display, the second line of the Two cats ticker): `integration_claude` is Claude Code (its pill on the island is
 * labelled the same), `agent_<tag>` is the agent's name. Any other ID is itself.
 */
export function agentLabel(pillId: string): string {
  const tag = pillId === "integration_claude" ? "claude" : pillId.startsWith("agent_") ? pillId.slice(6) : pillId;
  if (Object.hasOwn(AGENT_NAMES, tag)) return AGENT_NAMES[tag];
  return tag ? tag[0].toUpperCase() + tag.slice(1) : pillId;
}

/** The colour of an agent pill: the Claude Code pill's for Claude Code, `agentColor` for `agent_<tag>`, a grey for anything else. */
export function pillColor(pillId: string): string {
  if (pillId === "integration_claude") return "#F5F6F8";
  return pillId.startsWith("agent_") ? agentColor(pillId.slice(6)) : "#8D9098";
}
