// The Sidekick's scripted runs for the dev server (sub-project F1): `window.__nm.run.recap()` and the others feed the island the hook events a real agent would send, and move the Sidekick's
// clock forward (`__nm.skew(ms)`), so that a recap after minutes away, a loop, a request nobody answered and a quiet agent can be looked at in seconds and in pictures. The dev server only:
// main.ts loads this behind `import.meta.env.DEV`, so a release build does not contain it. Nothing here is the app's own behaviour: it only sends events and moves a clock.

import type { Island } from "../island/island";
import type { HookPayload } from "../island/hooks";
import { Skew } from "./appenv";
import type { Sidekick } from "./controller.ts";

const MIN = 60_000;

export function sidekickScenarios(island: Island, sk: Sidekick, hook: (p: HookPayload) => void) {
  const ev = (name: string, extra: Partial<HookPayload> = {}, agent?: string) =>
    hook({ hook_event_name: name, session_id: agent ? `dev-${agent}` : "dev-claude", cwd: "C:/work/app", ...(agent ? { nm_agent: agent } : {}), ...extra });
  const bash = (command: string, name = "PostToolUse", agent?: string) => ev(name, { tool_name: agent ? "run_shell_command" : "Bash", tool_input: { command } }, agent);
  const edit = (file: string) => ev("PostToolUse", { tool_name: "Edit", tool_input: { file_path: `C:/work/app/src/${file}` } });
  // The launch greeting is a view of its own: a note waits for it (as it should), so each run starts by folding the island, which ends it.
  const quietIsland = () => island.collapse();
  const skew = (ms: number) => {
    Skew.ms += ms;
    sk.evaluate();
  };
  return {
    skew,
    /** Locked, an agent works for five minutes and finishes, unlocked: the recap. */
    recap() {
      quietIsland();
      sk.presenceSignal("lock");
      ev("PreToolUse", { tool_name: "Edit", tool_input: { file_path: "C:/work/app/src/a.ts" } });
      edit("a.ts");
      edit("b.ts");
      bash("npm test");
      ev("PostToolUseFailure", { tool_name: "Bash", tool_input: { command: "npm test" } });
      skew(5 * MIN);
      ev("Stop");
      sk.presenceSignal("unlock");
    },
    /** The same step four times. */
    loop() {
      quietIsland();
      for (let i = 0; i < 4; i++) bash("npm test");
    },
    errors() {
      quietIsland();
      for (let i = 0; i < 3; i++) ev("PostToolUseFailure", { tool_name: "Bash", tool_input: { command: `build step ${i}` } });
    },
    /** A request nobody has answered for a minute, its card not on screen. */
    waiting() {
      ev("PermissionRequest", { tool_name: "Bash", tool_input: { command: "npm install left-pad" }, request_id: "dev-wait" });
      island.collapse();
      skew(61_000);
    },
    quiet() {
      quietIsland();
      bash("npm run build");
      skew(5 * MIN + 1000);
    },
    /** A permission request of each risk, for the card: `run.card("high")`, `"medium"` or `"low"`. */
    card(risk: "high" | "medium" | "low" = "high") {
      const input = { high: { command: "git push --force origin main" }, medium: { command: "npm install left-pad" }, low: { command: "npm test" } }[risk];
      ev("PermissionRequest", { tool_name: "Bash", tool_input: input, request_id: `dev-card-${risk}` });
    },
    /** Two other agents running, for the drop on an agent's cat (open `?display=perAgent`). */
    agents() {
      bash("ls", "PreToolUse", "gemini");
      bash("ls", "PreToolUse", "antigravity");
    },
  };
}
