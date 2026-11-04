import test from "node:test";
import assert from "node:assert/strict";
import { ProjectsModel } from "../../src/projects/model.ts";
import { brandOf, cloudLine, contextOf, localDay, systemFor } from "../../src/companion/turn.ts";
import { CompanionCore } from "../../src/companion/core.generated.ts";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";

// The companion in every turn (F3a-tauri, Task 5): the page builds the system text from the Projects registry, the settings and the
// state; a Windows path and a stepped-back wait are fed through the real ProjectsModel.hook, not through a hand-made view.

const T = Date.UTC(2026, 9, 26, 12);
const TODAY = "2026-10-26";

function settings(companion = {}, character) {
  const cat = character ? { ...DEFAULT_SETTINGS.cat, character } : DEFAULT_SETTINGS.cat;
  return { ...DEFAULT_SETTINGS, cat, companion: { ...DEFAULT_SETTINGS.companion, ...companion } };
}

function feed() {
  return new ProjectsModel({ home: "C:\\Users\\sam", now: () => T });
}

test("a Windows path in a step never reaches the prompt or the Right now block", () => {
  const m = feed();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app" });
  m.hook({ hook_event_name: "PreToolUse", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app", tool_name: "Edit", tool_input: { file_path: "C:\\Users\\sam\\Code\\app\\src\\main.ts" } });
  const ctx = contextOf({ view: m.view(), attention: false, mood: "working" });
  const sys = systemFor(ctx, settings(), TODAY);
  assert.match(ctx.rightNow, /app/, "the project is named");
  assert.match(ctx.rightNow, /Edits · main\.ts/, "the step is kept, cleaned: the file's last part, never dropped as clean");
  for (const text of [sys, ctx.rightNow]) {
    assert.doesNotMatch(text, /\\/, "no separator reaches the prompt");
    assert.doesNotMatch(text, /C:\/|Users|Code\/app/, "no path reaches the prompt");
  }
});

test("a wait stepped back into its own app keeps the chat quiet, and the prompt says so", () => {
  const m = feed();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app" });
  m.hook({ hook_event_name: "PermissionRequest", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app", tool_name: "Bash", tool_input: { command: "npm test" } }, "Windows Terminal");
  const ctx = contextOf({ view: m.view(), attention: false, mood: "thinking" });
  assert.equal(ctx.quiet, true, "the stepped-back wait counts as waiting");
  assert.match(ctx.rightNow, /Waiting in Windows Terminal/, "the Right now block names the app the wait sits in");
  const sys = systemFor(ctx, settings(), TODAY);
  assert.doesNotMatch(sys, /npm test/, "the command the wait is for never reaches the prompt");
  assert.doesNotMatch(ctx.rightNow, /npm test/, "nor the Right now block");
  assert.ok(sys.includes(CompanionCore.QUIET_LINE), "the quiet line is in the prompt");
  assert.ok(CompanionCore.moodHint("thinking") !== "" && !sys.includes(CompanionCore.moodHint("thinking")), "and no mood hint");
});

test("with nothing waiting the same chat is not quiet, and the mood hint is there", () => {
  const m = feed();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app" });
  const ctx = contextOf({ view: m.view(), attention: false, mood: "thinking" });
  assert.equal(ctx.quiet, false);
  const sys = systemFor(ctx, settings(), TODAY);
  assert.ok(!sys.includes(CompanionCore.QUIET_LINE));
  assert.ok(sys.includes(CompanionCore.moodHint("thinking")));
});

test("the same wait fed without waitIn is quiet too, but names no app: the note is the step-back's alone", () => {
  const m = feed();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app" });
  m.hook({ hook_event_name: "PermissionRequest", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app", tool_name: "Bash", tool_input: { command: "npm test" } });
  const ctx = contextOf({ view: m.view(), attention: false, mood: "thinking" });
  assert.equal(ctx.quiet, true, "still waiting, so still quiet");
  assert.doesNotMatch(ctx.rightNow, /Waiting in/, "no step-back note without a host");
});

test("an approval card on the screen is quiet even with no session waiting", () => {
  const m = feed();
  const ctx = contextOf({ view: m.view(), attention: true, mood: "working" });
  assert.equal(ctx.quiet, true);
});

test("a sleeping Main cat's mood reaches the prompt as its own hint", () => {
  const ctx = contextOf({ view: feed().view(), attention: false, mood: "sleeping" });
  assert.ok(CompanionCore.moodHint("sleeping") !== "", "sleeping has a fixed sentence");
  assert.ok(systemFor(ctx, settings(), TODAY).includes(CompanionCore.moodHint("sleeping")));
});

test("with See my sessions off the prompt holds no Right now block", () => {
  const m = feed();
  m.hook({ hook_event_name: "UserPromptSubmit", session_id: "a", cwd: "C:\\Users\\sam\\Code\\app" });
  const ctx = contextOf({ view: m.view(), attention: false, mood: "working" });
  assert.ok(systemFor(ctx, settings(), TODAY).includes(CompanionCore.RIGHT_NOW_HEAD), "on: the block is there");
  assert.ok(!systemFor(ctx, settings({ seeSessions: false }), TODAY).includes(CompanionCore.RIGHT_NOW_HEAD), "off: it is not");
});

test("the Main cat's label and the date come from the settings; no account name is read", () => {
  const ctx = contextOf({ view: feed().view(), attention: false, mood: "idle" });
  const sys = systemFor(ctx, settings(), TODAY);
  assert.ok(sys.includes("You are Shrimpy, a cat who lives at the top of the user's screen"), "Shrimpy by default");
  assert.ok(sys.includes(`Today is ${TODAY}.`));
  assert.ok(systemFor(ctx, settings({}, "momo"), TODAY).includes("You are Momo, a cat"), "the Main cat's own label");
  assert.doesNotMatch(sys, /Mac\b/, "the Windows words, not the Mac's");
});

test("localDay is the local calendar day as YYYY-MM-DD", () => {
  assert.equal(localDay(new Date(2026, 0, 5, 10)), "2026-01-05");
  assert.equal(localDay(new Date(2026, 11, 31, 23, 59)), "2026-12-31");
});

test("brandOf names the provider's company, and any other provider by its id", () => {
  assert.deepEqual(["anthropic", "claudeCode", "openai", "google", "custom", "other"].map(brandOf), ["Anthropic", "Anthropic", "OpenAI", "Google", "your custom server", "other"]);
});

test("the cloud line is shown once per provider, only for a cloud brain while See my sessions is on", () => {
  const s = settings().companion;
  const once = cloudLine({ provider: "anthropic", placement: "cloud" }, s);
  assert.ok(once && once.line.includes("Anthropic") && once.shown.join(",") === "anthropic");
  assert.equal(cloudLine({ provider: "anthropic", placement: "cloud" }, { ...s, cloudNoticeShown: ["anthropic"] }), null, "already shown");
  assert.equal(cloudLine({ provider: "ollama", placement: "local" }, s), null, "a local brain never gets it");
  assert.equal(cloudLine(null, s), null, "no resolution, no line");
  assert.equal(cloudLine({ provider: "openai", placement: "cloud" }, { ...s, seeSessions: false }), null, "not while See my sessions is off");
  assert.deepEqual(cloudLine({ provider: "openai", placement: "cloud" }, { ...s, cloudNoticeShown: ["google"] }).shown, ["google", "openai"]);
});

test("a custom server off this computer (placement network) gets the cloud line, named your custom server, once", () => {
  const s = settings().companion;
  const once = cloudLine({ provider: "custom", placement: "network" }, s);
  assert.ok(once && once.line.includes("with your custom server.") && once.shown.join(",") === "custom");
  assert.equal(cloudLine({ provider: "custom", placement: "network" }, { ...s, cloudNoticeShown: ["custom"] }), null, "already shown");
  assert.equal(cloudLine({ provider: "custom", placement: "network" }, { ...s, seeSessions: false }), null, "not while See my sessions is off");
  assert.equal(cloudLine({ provider: "custom", placement: "local" }, s), null, "a custom server on this computer never gets it");
});
