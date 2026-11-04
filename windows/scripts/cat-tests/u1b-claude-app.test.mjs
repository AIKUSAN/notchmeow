import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { finishedAction, openRoute } from "../../src/core/openagent.ts";

test("the ↗ of a Claude Code session from the Claude app starts the app where there is one, and nothing where there is none", () => {
  assert.equal(openRoute("integration_claude", true, true), "claude-app");
  assert.equal(openRoute("integration_claude", false, true), "none", "Linux: no official app, so the ↗ does nothing rather than open VS Code on the wrong thing");
  assert.equal(openRoute("integration_claude", true, false), "vscode", "Claude Code is as it was");
  assert.equal(openRoute("integration_claude", false, false), "vscode");
  assert.equal(openRoute("agent_gemini", true, true), "other");
  assert.equal(openRoute(null, true, true), "other");
});

test("the finished card and the Sidekick's nudge: Open Claude for a session from the app, Open terminal for the rest, no button on Linux for the app", () => {
  assert.deepEqual(finishedAction("integration_claude", true, true), { label: "Open Claude", kind: "claude-app" });
  assert.equal(finishedAction("integration_claude", false, true), null);
  assert.deepEqual(finishedAction("integration_claude", false, false), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction("agent_gemini", true, true), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction(undefined, true, false), { label: "Open terminal", kind: "terminal" });
});

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the page asks Rust to start the app from the four places that open an agent's app", () => {
  const island = read("src/island/island.ts"), views = read("src/views/views.ts"), bridge = read("src/core/bridge.ts"), main = read("src/main.ts"), state = read("src/core/state.ts");
  assert.match(bridge, /openClaudeApp: \(\) => call<boolean>\("open_claude_app"\)/);
  assert.match(bridge, /claudeApp: boolean;/);
  assert.match(main, /if \(boot\) State\.claudeApp = boot\.claudeApp;/);
  assert.match(state, /claudeApp = false;/);
  assert.match(island, /if \(openRoute\(task\.id, State\.claudeApp, State\.claudeAppHost\) === "claude-app"\) void Bridge\.openClaudeApp\(\);/, "the pill's ↗");
  assert.match(island, /openTerminal: \(\) => this\.openAgent\(State\.focusTask\?\.id, State\.focusTask\?\.sessionCwd \?\? null\),/, "the finished card");
  assert.match(island, /this\.openAgent\(id, State\.tasks\.find\(\(t\) => t\.id === id\)\?\.sessionCwd \?\? null\);/, "the Sidekick's nudge");
  assert.match(island, /if \(openRoute\(agentId, State\.claudeApp, State\.claudeAppHost\) === "claude-app"\) void Bridge\.openClaudeApp\(\);/, "a file dropped on the pill's cat");
  assert.match(views, /const open = btn\("Open terminal", "primary", \(\) => actions\.openTerminal\(\)\);/);
  assert.match(views, /const act = finishedAction\(note\.agentId, State\.claudeApp, State\.claudeAppHost\);/);
});

test("Rust starts only what the resolver picks, through the shell, with no command interpreter", () => {
  const lib = read("src-tauri/src/lib.rs"), win = read("src-tauri/src/platform/windows.rs"), linux = read("src-tauri/src/platform/linux.rs");
  assert.match(lib, /async fn open_claude_app\(\) -> bool \{\s*blocking\(platform::open_claude_app\)\.await\.unwrap_or\(false\)/);
  assert.match(lib, /open_claude_app,/);
  assert.match(lib, /claude_app: platform::CLAUDE_APP,/);
  const body = /pub fn open_claude_app\(\) -> bool \{[\s\S]*?\n\}\n/.exec(win)?.[0] ?? "";
  assert.ok(body.length > 100, "the Windows function exists");
  assert.match(body, /crate::claude_app::pick\(/);
  assert.match(body, /Command::new\("explorer\.exe"\)/);
  assert.match(body, /shell:AppsFolder\\\\\{id\}/);
  assert.match(body, /Get-StartApps/);
  assert.doesNotMatch(body, /"cmd"|"cmd\.exe"|Command::new\("sh"\)|-c"|\/c/, "no command interpreter ever sees a name from the system");
  assert.match(linux, /pub const CLAUDE_APP: bool = false;/);
  assert.match(linux, /pub fn open_claude_app\(\) -> bool \{\s*false\s*\}/);
});
