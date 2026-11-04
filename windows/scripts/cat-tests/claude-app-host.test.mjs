import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CLAUDE_DESKTOP_TAG, finishedAction, isClaudeDesktopTag, openRoute } from "../../src/core/openagent.ts";

// A Claude Code session from the Claude desktop app belongs to the Claude Code pill (integration_claude); its host is the Claude app. hooks.ts needs a browser,
// so its routing is pinned by source, as the other handlers are (kitten-wiring.test.mjs).
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the relay's tag is recognised exactly, and it is the tag the relay sends", () => {
  assert.equal(CLAUDE_DESKTOP_TAG, "claude-desktop");
  assert.deepEqual(
    ["claude-desktop", "Claude-Desktop", "claude-desktop-x", "", undefined, null].map((t) => isClaudeDesktopTag(t)),
    [true, false, false, false, false, false],
  );
  assert.match(read("hook/src/agents.rs"),/pub const CLAUDE_DESKTOP: &str = "claude-desktop";/);
});

test("a Claude Code session from the Claude app is opened by the Claude Code pill's ↗, and nothing else changes", () => {
  assert.equal(openRoute("integration_claude", true, true), "claude-app", "Windows: the app is started");
  assert.equal(openRoute("integration_claude", false, true), "none", "no app found, or Linux: nothing, rather than VS Code on the wrong thing");
  assert.equal(openRoute("integration_claude", true, false), "vscode", "a session in VS Code or a terminal is as it was");
  assert.equal(openRoute("integration_claude", false, false), "vscode");
  assert.equal(openRoute("agent_gemini", true, true), "other", "only the Claude Code pill can host the app");
  assert.equal(openRoute(null, true, true), "other");
});

test("the finished card and the Sidekick's nudge: Open Claude for a session from the app, Open terminal for the rest, no button on Linux", () => {
  assert.deepEqual(finishedAction("integration_claude", true, true), { label: "Open Claude", kind: "claude-app" });
  assert.equal(finishedAction("integration_claude", false, true), null);
  assert.deepEqual(finishedAction("integration_claude", true, false), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction("agent_gemini", true, true), { label: "Open terminal", kind: "terminal" });
  assert.deepEqual(finishedAction(undefined, true, false), { label: "Open terminal", kind: "terminal" });
});

test("hooks.ts routes the tag to the Claude Code pill, records the Claude app as its host, and declines its permission request with no card", () => {
  const hooks = read("src/island/hooks.ts");
  assert.match(hooks, /import \{[^}]*isClaudeDesktopTag[^}]*\} from "\.\.\/core\/openagent\.ts";/);
  assert.match(hooks, /const fromClaudeApp = isClaudeDesktopTag\(payload\.nm_agent\);/);
  assert.match(hooks, /const validAgent = fromClaudeApp \? null : validateAgent\(payload\.nm_agent\);/, "the tag is no agent of its own");
  assert.match(hooks, /const agentId = validAgent \? `agent_\$\{validAgent\}` : CLAUDE_ID;/, "so the event is Claude Code's pill");
  assert.match(hooks, /if \(agentId === CLAUDE_ID\) State\.claudeAppHost = fromClaudeApp;/, "the pill's session records its host");
  assert.match(hooks, /case "PermissionRequest": \{[\s\S]*?if \(isExternalAgent \|\| fromClaudeApp\) \{\s*if \(payload\.request_id\) void Bridge\.approvalDecline\(payload\.request_id\);/, "declined at once, no card");
  const state = read("src/core/state.ts");
  assert.match(state, /claudeAppHost = false;/);
});

test("the open actions read the host of the Claude Code pill, at each call site", () => {
  const island = read("src/island/island.ts"), views = read("src/views/views.ts");
  assert.match(island, /if \(openRoute\(task\.id, State\.claudeApp, State\.claudeAppHost\) === "claude-app"\) void Bridge\.openClaudeApp\(\);/, "the pill's ↗");
  assert.match(island, /const act = finishedAction\(pillId, State\.claudeApp, State\.claudeAppHost\);/, "the finished card and the nudge");
  assert.match(island, /if \(openRoute\(agentId, State\.claudeApp, State\.claudeAppHost\) === "claude-app"\) void Bridge\.openClaudeApp\(\);/, "a file dropped on the pill's cat");
  assert.match(views, /const act = finishedAction\(State\.focusTask\?\.id, State\.claudeApp, State\.claudeAppHost\);/);
  assert.match(views, /const act = finishedAction\(note\.agentId, State\.claudeApp, State\.claudeAppHost\);/);
  assert.doesNotMatch(island + views, /CLAUDE_APP_PILL/, "nothing keys on the frozen pill ID any more");
});
