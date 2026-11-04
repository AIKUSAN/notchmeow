import test from "node:test";
import assert from "node:assert/strict";
import { code } from "../projects-tests/util.mjs";
import { isImageName, keepWaiting, quickNote } from "../../src/companion/quick.ts";
import { QUICK_NO_VISION } from "../../src/companion/core.ts";
import { State } from "../../src/core/state.ts";
import { startNewChat } from "../../src/companion/session.ts";
import { forgetDrop } from "../../src/core/feature.ts";
import { applyToIsland, checkToIsland, windowLink } from "../../src/companion/windowlink.ts";
import { NO_MODEL_NOTE } from "../../src/companion/chrome.ts";

/** The text of one function of chat.ts, from its header to the closing brace at the function's own indent (two spaces). */
function bodyOf(src, header) {
  const start = src.indexOf(header);
  assert.ok(start > 0, `${header} is found`);
  return src.slice(start, src.indexOf("\n  }\n", start));
}

// Quick actions and the pasted screenshot (F3a-tauri, Task 10): the quick card's rules, the waiting file kept across a new chat, and the wiring the chat
// view and the bridge must keep (one request builder, one reply cleaner, no clipboard read, no HTML from a model).

test("isImageName accepts the picture extensions in any case, paths included, and nothing else", () => {
  for (const name of ["shot.png", "PHOTO.JPG", "a.jpeg", "b.GIF", "c.webp", "C:\\dev\\x\\Shot.PNG", "/home/dev/pic.Jpg"]) {
    assert.equal(isImageName(name), true, name);
  }
  for (const name of ["notes.txt", "png", "archive.png.zip", "pic.pngx", "", "readme.md"]) {
    assert.equal(isImageName(name), false, name);
  }
});

test("quickNote gives the vision words for a model that can't see, and the event's own words otherwise", () => {
  assert.equal(quickNote({ type: "problem", kind: "cant_see", message: "I can't see images." }), QUICK_NO_VISION);
  assert.equal(quickNote({ type: "problem", kind: "rejected", message: "Files over 25 MB are too big for me." }), "Files over 25 MB are too big for me.");
  assert.equal(quickNote({ type: "error", kind: "network", message: "Couldn't reach OpenAI. Check your connection." }), "Couldn't reach OpenAI. Check your connection.");
});

test("keepWaiting puts back the waiting file that a new chat forgets, and only that file", () => {
  const waiting = { droppedFile: { name: "shot.png", path: "/home/dev/inbox/shot.png" }, promptContext: { kind: "file", name: "shot.png", path: "/home/dev/inbox/shot.png" }, pendingAttachment: "/home/dev/inbox/shot.png", dropReader: "Claude" };
  const s = { ...waiting };
  const restore = keepWaiting(s);
  forgetDrop(s);
  assert.equal(s.pendingAttachment, null, "the drop helper forgets the file");
  restore();
  assert.deepEqual(s, waiting, "the file is back exactly as it was");
});

test("a new chat forgets the waiting file, so the screenshot flow must keep it across startNewChat", () => {
  State.pendingAttachment = "/home/dev/inbox/shot.png";
  State.droppedFile = { name: "shot.png", path: "/home/dev/inbox/shot.png" };
  State.promptContext = { kind: "file", name: "shot.png", path: "/home/dev/inbox/shot.png" };
  const link = { release() {}, approval: () => null, decide() {}, session() {}, context: () => ({}) };
  const chat = { reset() {}, loadTurns() {} };
  const restore = keepWaiting(State);
  startNewChat(link, chat);
  assert.equal(State.pendingAttachment, null, "startNewChat forgets the file");
  restore();
  assert.equal(State.pendingAttachment, "/home/dev/inbox/shot.png");
  assert.equal(State.droppedFile?.name, "shot.png");
  State.pendingAttachment = null;
  State.droppedFile = null;
  State.promptContext = null;
});

test("the chat view sends Fix, Rewrite and Explain through quickRequest with the pc device, three times", () => {
  const chat = code("views/chat.ts");
  assert.equal(chat.match(/quickRequest\([^)]*"pc"\)/g)?.length, 3, "fix or rewrite, explain, and explain this screenshot");
  assert.equal(chat.split("Bridge.aiQuick(").length - 1, 1, "only Fix and Rewrite use the quick turn; Explain goes into a normal chat turn");
  assert.match(chat, /Bridge\.aiQuick\("chat", r\.system, r\.user, \[\], /);
});

test("the screenshot flow captures the waiting file before the new chat and restores it after", () => {
  const chat = code("views/chat.ts");
  const start = chat.indexOf("function explainScreenshot(");
  assert.ok(start > 0, "the screenshot flow is found");
  const body = chat.slice(start, chat.indexOf("\n  }\n", start));
  const keepAt = body.indexOf("keepWaiting(");
  const newChatAt = body.indexOf("startNewChat(");
  const restoreAt = body.indexOf("restore()");
  assert.ok(keepAt > 0 && newChatAt > keepAt, "keepWaiting is taken before startNewChat");
  assert.ok(restoreAt > newChatAt, "the file is put back after startNewChat");
  assert.match(body, /const attachments = \[shot\];/, "the new turn carries the screenshot");
  assert.match(body, /void ask\(\{ text: r\.user, attachments, feature: "files"/, "and asks with it, as the files setting");
});

test("the quick card and its turn never read the clipboard, and no model text becomes HTML", () => {
  const sources = [code("views/chat.ts"), code("companion/quick.ts"), code("companion/chrome.ts"), code("companion/session.ts")];
  for (const src of sources) {
    assert.doesNotMatch(src, /navigator\.clipboard/);
    assert.doesNotMatch(src, /innerHTML/);
  }
  assert.match(code("views/chat.ts"), /Bridge\.copyText\(/, "copy goes through the bridge");
});

test("the bridge names the quick and picture commands as the frozen names", () => {
  const bridge = code("core/bridge.ts");
  assert.match(bridge, /"ai_quick"/);
  assert.match(bridge, /"ingest_png"/);
  assert.match(bridge, /ingestPng: \(bytes: Uint8Array\)/);
});

test("the quick card's spacing is scoped under the chat body and carries no colour or font of its own", () => {
  const css = code("companion/companion.css").replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = css.split("}").map((r) => r.trim()).filter((r) => r.includes(".cm-"));
  assert.ok(rules.length >= 3, "the card has rules");
  for (const rule of rules) {
    const selector = rule.slice(0, rule.indexOf("{"));
    assert.match(selector, /^\.chat-body > (?:\.chip-row )?\.cm-/, selector);
    assert.doesNotMatch(rule, /\b(color|background|font|border-color)\b|#[0-9a-f]{3,6}\b/i, rule);
  }
});

// Quick round 1: a quick Claude run is the chat's session (a pill never), Send and the picture wait for a running quick action, × stops it, a run that
// gets no brain says so, and the cloud line is one helper for the send and the quick flows.

test("a window's forget message is checked, and the island forgets the id only while the chat is popped out", () => {
  assert.deepEqual(checkToIsland({ kind: "forget", id: "s1" }), { kind: "forget", id: "s1" });
  assert.equal(checkToIsland({ kind: "forget" }), null);
  assert.equal(checkToIsland({ kind: "forget", id: "" }), null);
  const sent = [];
  windowLink((m) => sent.push(m)).forget("s1");
  assert.deepEqual(sent, [{ kind: "forget", id: "s1" }]);
  const seen = [];
  const link = { forget: (id) => seen.push(id) };
  State.chatPoppedOut = false;
  applyToIsland({ kind: "forget", id: "s1" }, link);
  assert.deepEqual(seen, [], "not popped out: nothing is applied");
  State.chatPoppedOut = true;
  applyToIsland({ kind: "forget", id: "s1" }, link);
  assert.deepEqual(seen, ["s1"]);
  State.chatPoppedOut = false;
});

test("the quick run registers its Claude session as the chat's, before the stale check, and forgets it after a grace", () => {
  const chat = code("views/chat.ts");
  const quick = bodyOf(chat, "  async function quickFix(");
  const claudeAt = quick.indexOf('e.type === "claudeSession"');
  assert.ok(claudeAt > 0 && quick.indexOf("link.session(e.sessionId, e.retired);") > claudeAt, "the session is registered through the chat's link");
  assert.ok(claudeAt < quick.indexOf("State.quickResult !== card"), "a dismissed card still registers a run that is going");
  assert.ok(quick.indexOf("forgetQuickSession();") < quick.indexOf("const card: QuickResult"), "the previous quick session goes at the next quick action");
  assert.match(quick, /if \(quickSession !== null\) quickSessionTimer = window\.setTimeout\(forgetQuickSession, QUICK_SESSION_GRACE_MS\);/, "one grace timer, only when a session ran");
  assert.match(chat, /const QUICK_SESSION_GRACE_MS = 3000;/);
  assert.match(bodyOf(chat, "  function forgetQuickSession("), /window\.clearTimeout\(quickSessionTimer\)[\s\S]*link\.forget\(quickSession\)/);
});

test("Send, Enter and the explain flows wait for a running quick action and keep the text in the field", () => {
  const chat = code("views/chat.ts");
  const submit = bodyOf(chat, "  async function submit() {");
  const gate = submit.indexOf("if (State.quickResult?.running) return;");
  assert.ok(gate > 0 && gate < submit.indexOf("const text = input.value.trim();"), "the gate is before the text is read and cleared");
  assert.ok(submit.indexOf("if (sending) {") < gate, "a reply that streams still answers Stop first");
  assert.match(bodyOf(chat, "  async function explainText("), /sending \|\| State\.quickResult\?\.running/);
  assert.match(bodyOf(chat, "  async function explainScreenshot("), /sending \|\| State\.quickResult\?\.running/);
  assert.match(chat, /send\.toggleAttribute\("disabled", !sending && \(quick\?\.running \?\? false\)\);/);
  assert.match(chat, /const held = sending \|\| \(State\.quickResult\?\.running \?\? false\);/);
});

test("× stops a running quick action, and a finished card only goes", () => {
  const chat = code("views/chat.ts");
  const close = bodyOf(chat, "  function closeQuick(");
  assert.match(close, /if \(State\.quickResult\?\.running\) void Bridge\.aiCancel\(\);/);
  assert.ok(close.indexOf("aiCancel") < close.indexOf("State.quickResult = null"));
});

test("a quick run that gets no brain says so in the card, with the Settings words", () => {
  const chat = code("views/chat.ts");
  const quick = bodyOf(chat, "  async function quickFix(");
  assert.match(quick, /e\.type === "emptyState"[\s\S]*card\.note = NO_MODEL_NOTE;/);
  assert.equal(NO_MODEL_NOTE, "No model yet: add a cloud key or start a local model.");
  assert.ok(code("settings/ai.ts").includes(NO_MODEL_NOTE), "the same sentence Settings shows for no model");
});

test("a pasted picture refreshes the model before the cloud line can read it", () => {
  const chat = code("views/chat.ts");
  const take = bodyOf(chat, "  async function takePicture(");
  assert.match(take, /await refreshModel\(\);\s*State\.dropReader = resolution\?\.reader \?\? null;/);
  assert.doesNotMatch(take, /Bridge\.aiResolve\("files"\)/);
});

test("submit and the quick flows share one cloud-line helper, defined before submit", () => {
  const chat = code("views/chat.ts");
  const submit = bodyOf(chat, "  async function submit() {");
  assert.match(submit, /cloudNoticeNow\(\);/);
  assert.doesNotMatch(submit, /cloudLine\(/);
  assert.ok(chat.indexOf("function cloudNoticeNow(") < chat.indexOf("function submit("), "defined above submit");
  assert.equal(chat.split("cloudLine(resolution, State.settings.companion)").length - 1, 1, "the line is computed in one place");
});
