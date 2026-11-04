// The dev scenarios of the Projects view (P-tauri, Task 4): scripted Claude Code sessions in made-up folders under C:/dev/, each step a hook payload the registry
// reads (dev.ts feeds them to the island). Session ids start with `dev-`; the `end` scenario ends them all. No real name, path or prompt is in here.

export interface ProjectScenarioStep { at: number; payload: Record<string, unknown> }
export interface ProjectScenario { note: string; steps: readonly ProjectScenarioStep[] }

const at = (n: number, payload: Record<string, unknown>): ProjectScenarioStep => ({ at: n, payload });
const NOTCH = "C:/dev/Code/notchmeow";
const WORKTREE = `${NOTCH}/.claude/worktrees/p-tauri`;

export const PROJECT_SCENARIOS: Readonly<Record<string, ProjectScenario>> = {
  two: {
    note: "A main and a side session in notchmeow (the side in a worktree), two subagents, a second project site; a Stop.",
    steps: [
      at(0, { hook_event_name: "SessionStart", session_id: "dev-main", cwd: NOTCH }),
      at(1000, { hook_event_name: "UserPromptSubmit", session_id: "dev-main", cwd: NOTCH, prompt: "dev prompt" }),
      at(2000, { hook_event_name: "PreToolUse", session_id: "dev-main", cwd: NOTCH, tool_name: "Bash", tool_input: { command: "swift test" } }),
      at(3000, { hook_event_name: "SubagentStart", session_id: "dev-main", cwd: NOTCH, agent_id: "dev-sub-1", agent_type: "Explore" }),
      at(3500, { hook_event_name: "SubagentStart", session_id: "dev-main", cwd: NOTCH, agent_id: "dev-sub-2", agent_type: "Plan" }),
      at(4000, { hook_event_name: "PreToolUse", session_id: "dev-side", cwd: WORKTREE, tool_name: "Read", tool_input: { file_path: `${WORKTREE}/windows/src/a.ts` } }),
      at(5000, { hook_event_name: "PreToolUse", session_id: "dev-site", cwd: "C:/dev/Code/site", tool_name: "Grep", tool_input: { pattern: "TODO" } }),
      at(6000, { hook_event_name: "Stop", session_id: "dev-main", cwd: NOTCH, stop_hook_active: false }),
    ],
  },
  appWait: {
    note: "A Claude desktop app session and its permission request: waiting in the Claude App, counted, never a card.",
    steps: [
      at(0, { hook_event_name: "UserPromptSubmit", session_id: "dev-app", cwd: "C:/dev/Code/app", nm_agent: "claude-desktop", prompt: "dev prompt" }),
      at(1000, { hook_event_name: "PermissionRequest", session_id: "dev-app", cwd: "C:/dev/Code/app", nm_agent: "claude-desktop", tool_name: "Bash", tool_input: { command: "npm test" } }),
    ],
  },
  cardWait: {
    note: "A terminal session's permission request: waiting, and the notch card as today.",
    steps: [
      at(0, { hook_event_name: "UserPromptSubmit", session_id: "dev-card", cwd: "C:/dev/Code/tools", term_program: "Apple_Terminal", prompt: "dev prompt" }),
      at(1000, { hook_event_name: "PermissionRequest", session_id: "dev-card", cwd: "C:/dev/Code/tools", term_program: "Apple_Terminal", tool_name: "Bash", tool_input: { command: "rm -rf build" } }),
    ],
  },
  collide: {
    note: "Two folders named notchmeow in different places: two projects, one name each, told apart by their folder.",
    steps: [
      at(0, { hook_event_name: "PreToolUse", session_id: "dev-col-a", cwd: NOTCH, tool_name: "Read", tool_input: { file_path: `${NOTCH}/README.md` } }),
      at(1000, { hook_event_name: "PreToolUse", session_id: "dev-col-b", cwd: "C:/dev/Old/notchmeow", tool_name: "Read", tool_input: { file_path: "C:/dev/Old/notchmeow/README.md" } }),
    ],
  },
  subagents: {
    note: "Three subagents of one session, one of them asking for a permission.",
    steps: [
      at(0, { hook_event_name: "SessionStart", session_id: "dev-subs", cwd: "C:/dev/Code/research" }),
      at(1000, { hook_event_name: "SubagentStart", session_id: "dev-subs", cwd: "C:/dev/Code/research", agent_id: "dev-sub-a", agent_type: "Explore" }),
      at(2000, { hook_event_name: "SubagentStart", session_id: "dev-subs", cwd: "C:/dev/Code/research", agent_id: "dev-sub-b", agent_type: "Plan" }),
      at(3000, { hook_event_name: "SubagentStart", session_id: "dev-subs", cwd: "C:/dev/Code/research", agent_id: "dev-sub-c", agent_type: "general-purpose" }),
      at(4000, { hook_event_name: "PermissionRequest", session_id: "dev-subs", cwd: "C:/dev/Code/research", agent_id: "dev-sub-b", tool_name: "Bash", tool_input: { command: "curl" } }),
    ],
  },
  many: {
    note: "Seven projects at once, for the +N count.",
    steps: [
      at(0, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-1", cwd: "C:/dev/Work/alpha", prompt: "dev prompt" }),
      at(1000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-2", cwd: "C:/dev/Work/bravo", prompt: "dev prompt" }),
      at(2000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-3", cwd: "C:/dev/Work/charlie", prompt: "dev prompt" }),
      at(3000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-4", cwd: "C:/dev/Work/delta", prompt: "dev prompt" }),
      at(4000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-5", cwd: "C:/dev/Work/echo", prompt: "dev prompt" }),
      at(5000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-6", cwd: "C:/dev/Work/foxtrot", prompt: "dev prompt" }),
      at(6000, { hook_event_name: "UserPromptSubmit", session_id: "dev-many-7", cwd: "C:/dev/Work/golf", prompt: "dev prompt" }),
    ],
  },
  other: {
    note: "Another agent (Gemini CLI) working: it counts as another agent, not as a Claude project.",
    steps: [
      at(0, { hook_event_name: "PreToolUse", session_id: "dev-gem", cwd: "C:/dev/Code/gem", nm_agent: "gemini", tool_name: "Bash", tool_input: { command: "npm run build" } }),
      at(1000, { hook_event_name: "Stop", session_id: "dev-gem", cwd: "C:/dev/Code/gem", nm_agent: "gemini" }),
    ],
  },
  end: {
    note: "Every dev session ends: the registry is empty again.",
    steps: [
      "dev-main", "dev-side", "dev-site", "dev-app", "dev-card", "dev-col-a", "dev-col-b", "dev-subs",
      "dev-many-1", "dev-many-2", "dev-many-3", "dev-many-4", "dev-many-5", "dev-many-6", "dev-many-7",
    ].map((id, i) => at(i * 100, { hook_event_name: "SessionEnd", session_id: id })),
  },
};
