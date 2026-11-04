import test from "node:test";
import assert from "node:assert/strict";
import { SessionLedger } from "../../src/sidekick/ledger.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { platformName } from "../../src/sidekick/platform.ts";
import { Hub } from "../../src/sidekick/hub.ts";
import { source } from "./util.mjs";

const MIN = 60_000;
const idle = async () => null;
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
const SECRETS = ["SECRET-PROMPT", "SECRET-OUT", "SECRET-WORDS", "SECRET-BODY", "SECRET-DIR", "SECRET-CMD", "SECRET-TRANSCRIPT", "SECRET-REPLY"];

test("a hook event goes into the ledger as a basename, a command key and counts; the event is handed back", () => {
  const l = new SessionLedger();
  const ev = l.feed(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\src\\main.ts", old_string: "a", new_string: "b" } }), 5000);
  assert.equal(ev.kind, "tool");
  assert.equal(ev.file, "main.ts");
  assert.equal(ev.project, "app");
  const s = l.snapshot.sessions[0];
  assert.deepEqual([s.agentId, s.sessionId, s.state, s.project], ["integration_claude", "S1", "thinking", "app"]);
  assert.deepEqual(s.ring.map((r) => [r.kind, r.tool, r.file, r.ok]), [["tool", "Edit", "main.ts", true]]);
  assert.equal(l.live.length, 1);
});

test("an event the ledger does not know, and anything that is not a payload, change nothing and throw nothing", () => {
  const l = new SessionLedger();
  for (const p of [null, undefined, 7, "x", [], {}, hook("Elicitation"), hook("")]) assert.equal(l.feed(p, 1000), null, JSON.stringify(p));
  assert.equal(l.feed(hook("Stop"), Number.NaN), null);
  assert.deepEqual(l.snapshot.sessions, []);
});

test("nothing secret is kept: not the prompt, the assistant's words, a transcript, a tool's output, a file's body, a command, a parent folder", () => {
  const l = new SessionLedger();
  const cwd = `C:\\Users\\${SECRETS[4]}\\app`;
  l.feed(hook("UserPromptSubmit", { prompt: SECRETS[0], transcript_path: `C:\\Users\\me\\.claude\\${SECRETS[6]}.jsonl`, cwd }), 1000);
  l.feed(hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `echo ${SECRETS[5]}` }, tool_response: { stdout: SECRETS[1] }, cwd }), 2000);
  l.feed(hook("PostToolUse", { tool_name: "Write", tool_input: { file_path: `${cwd}\\a.js`, content: SECRETS[3] }, cwd }), 3000);
  l.feed(hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: `curl https://${SECRETS[5]}` }, cwd }), 4000);
  l.feed(hook("Stop", { last_assistant_message: SECRETS[2], prompt_response: SECRETS[7], message: SECRETS[2], cwd }), 5000);
  const text = JSON.stringify(l.snapshot);
  for (const secret of SECRETS) assert.ok(!text.includes(secret), `${secret} is in the ledger`);
  assert.equal(l.snapshot.sessions[0].project, "app");
});

test("a payload the Windows relay cut at 2000 bytes (a long command, a long path) still feeds the ledger and keeps only a name and a key", () => {
  const l = new SessionLedger();
  const long = `${"x".repeat(2000)}…`;
  l.feed(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: long } }), 1000);
  l.feed(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: `C:\\${"d\\".repeat(900)}file.ts…` } }), 2000);
  const s = l.snapshot.sessions[0];
  assert.ok(JSON.stringify(s).length < 3000, "the ledger does not grow with the command");
  assert.ok(s.ring.every((r) => r.target.length <= 61 || r.target.startsWith("Bash#")));
});

test("a session ends at SessionEnd plus 30 minutes, or 12 hours after its last event, and at most 8 are kept", () => {
  const l = new SessionLedger();
  l.feed(hook("SessionStart"), 0);
  l.feed(hook("SessionEnd"), 10 * MIN);
  l.prune(10 * MIN + 30 * MIN);
  assert.equal(l.snapshot.sessions.length, 1, "30 minutes after the end it is still there");
  l.prune(10 * MIN + 30 * MIN + 1);
  assert.equal(l.snapshot.sessions.length, 0);
  l.feed(hook("SessionStart", { session_id: "quiet" }), 0);
  l.prune(12 * 60 * MIN);
  assert.equal(l.snapshot.sessions.length, 1);
  l.prune(12 * 60 * MIN + 1);
  assert.equal(l.snapshot.sessions.length, 0);
  for (let i = 0; i < 12; i++) l.feed(hook("PreToolUse", { session_id: `s${i}`, tool_name: "Bash", tool_input: { command: "ls" } }), 1000 + i);
  assert.equal(l.snapshot.sessions.length, 8);
  assert.ok(l.snapshot.sessions.every((s) => s.ring.length <= 40));
});

test("the ledger it hands out is never changed in place, and approvals answered and nudges marked go through the core", () => {
  const l = new SessionLedger();
  l.feed(hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } }), 1000);
  const before = JSON.stringify(l.snapshot);
  assert.equal(l.snapshot.sessions[0].state, "approval");
  const held = l.snapshot;
  l.answered("integration_claude", "S1", 2000);
  assert.equal(JSON.stringify(held), before, "the old snapshot is untouched");
  assert.equal(l.snapshot.sessions[0].pendingApprovalAt, null);
  l.markNudged(l.snapshot.sessions[0].key, 3000);
  assert.equal(l.snapshot.sessions[0].nudgedAt, 3000);
  l.clear();
  assert.deepEqual(l.snapshot.sessions, []);
});

test("the Sidekick feeds the ledger and never throws into the island's hook handler", () => {
  let t = 1000;
  const sk = new Sidekick({
    now: () => t, platform: "windows", idleSeconds: idle, settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
  });
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  assert.equal(sk.ledger.snapshot.sessions.length, 1);
  const hostile = {};
  Object.defineProperty(hostile, "hook_event_name", { get() { throw new Error("boom"); } });
  assert.doesNotThrow(() => sk.hook(hostile));
  assert.doesNotThrow(() => sk.hook(null));
  assert.doesNotThrow(() => sk.approvalAnswered(undefined, undefined));
  t = 2000;
  sk.approvalAnswered("integration_claude", "S1");
  assert.equal(sk.ledger.snapshot.sessions[0].ring.at(-1).kind, "approvalAnswered");
});

test("a fuzz of hook payloads never throws and never lets the ledger grow past its caps", () => {
  let seed = 11;
  const rnd = (n) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd", "Bogus"];
  const tools = ["Bash", "Edit", "Write", "Read", "Grep", "mcp__x__y", "", undefined, 7];
  const l = new SessionLedger();
  for (let i = 0; i < 3000; i++) {
    const p = { hook_event_name: names[rnd(names.length)], session_id: rnd(20) === 0 ? undefined : `s${rnd(30)}`, nm_agent: ["gemini", "antigravity", undefined, "BAD NAME", "claude"][rnd(5)], cwd: rnd(3) ? "C:\\w\\a" : 5, tool_name: tools[rnd(tools.length)], tool_input: rnd(4) ? { command: "x".repeat(rnd(50)), file_path: "C:\\a\\b" + rnd(9) } : [1, 2], agent_id: rnd(3) ? undefined : `a${rnd(5)}` };
    assert.doesNotThrow(() => l.feed(p, 1000 + i * 1000));
  }
  assert.ok(l.snapshot.sessions.length <= 8);
  assert.ok(l.snapshot.sessions.every((s) => s.ring.length <= 40 && Object.keys(s.subagents).length <= 20));
});

test("platformName: Windows is Windows, anything else here is Linux, and never the Mac", () => {
  assert.equal(platformName("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"), "windows");
  assert.equal(platformName("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15"), "linux");
  assert.equal(platformName("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"), "linux");
  assert.equal(platformName(""), "linux");
});

test("the hook handler feeds the ledger before it can refuse an event, after a chat's own run is set aside; the click on a card is recorded; main.ts installs the Sidekick", () => {
  const hooks = source("island/hooks.ts");
  const feed = hooks.indexOf("Hub.sk?.hook(payload);");
  assert.ok(feed > 0, "the feed call is there");
  assert.equal(hooks.split("Hub.sk?.hook(payload);").length - 1, 1, "once");
  assert.ok(hooks.indexOf('routeHook(payload, State.claudeSessions) === "chat"') < feed, "a chat's own Claude Code run is not a session: set aside before the feed");
  assert.ok(feed < hooks.indexOf("const name = payload.hook_event_name"), "before the event is read for the pill");
  assert.ok(feed < hooks.indexOf("State.pendingApproval.requestId !== requestId"), "before the one-card gate that declines a second request");
  assert.ok(feed < hooks.indexOf("if (isExternalAgent || fromClaudeApp) {\n        if (payload.request_id) void Bridge.approvalDecline"), "before the decline of an external agent's or a Claude app session's request");
  assert.match(source("island/island.ts"), /void Bridge\.approvalDecision\(req\.requestId, d\);\s*Hub\.sk\?\.approvalAnswered\(req\.pillId, req\.sessionId\);/);
  const main = source("main.ts");
  assert.match(main, /Hub\.sk = new Sidekick\(sidekickEnv\(.*\)\);/);
  assert.ok(main.search(/Hub\.sk = new Sidekick\(sidekickEnv\(.*\)\);/) < main.indexOf("registerHookHandlers(island);"), "installed before the first hook event can arrive");
  assert.match(source("sidekick/appenv.ts"), /now: \(\) => Date\.now\(\)( \+ Skew\.ms)?,\s*platform: platformName\(\)/);
  assert.equal(Hub.sk, null, "the module itself installs nothing");
});
