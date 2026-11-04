import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { code } from "../projects-tests/util.mjs";
import { State } from "../../src/core/state.ts";
import { matchStatusQuestion } from "../../src/sidekick/core.ts";
import { applyToIsland, checkToIsland, checkToWindow, windowLink } from "../../src/companion/windowlink.ts";

// The chat's pop-out window (F3a-tauri, Task 9). The relay between the island's page and the window's page carries DATA: each side checks the shape of every message
// before it acts (windowlink.ts), and the island honours a message only while the chat is popped out. The Rust side and the pages are pinned by source reads
// (comments blanked first), as the other Companion checks do.

const rawText = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
/** `//` and `/* *\/` comments replaced by spaces (Rust and TypeScript both), strings kept whole. */
const blank = (text) => text.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, " ")).replace(/(^|[^:"'\\])\/\/[^\n]*/g, (m, p) => p + " ".repeat(m.length - p.length));

const libRaw = rawText("src-tauri/src/lib.rs");
const lib = blank(libRaw); // same length as the raw text, so a marker found in the raw text is at the same place in this one
const caps = rawText("src-tauri/capabilities/default.json");
const vite = rawText("vite.config.ts");
const win = code("chatwin/main.ts");
const island = code("island/island.ts");
const main = code("main.ts");
const chat = code("views/chat.ts");
const views = code("views/views.ts");
const bridge = code("core/bridge.ts");
const state = code("core/state.ts");
const link = code("companion/link.ts");

const CONTEXT = { rightNow: "Projects: site (working)", quiet: false, mood: "working" };
const APPROVAL = { requestId: "r1", sessionId: "s1", tool: "Bash", command: "ls" };

function sender() {
  const sent = [];
  return { sent, send: (m) => sent.push(m) };
}

// ── windowLink ───────────────────────────────────────────────────────────────

test("windowLink answers with a quiet idle context and no approval before the island has said anything", () => {
  const l = windowLink(() => {});
  assert.deepEqual(l.context(), { rightNow: "", quiet: false, mood: "idle" });
  assert.equal(l.approval(), null);
});

test("a context message is what context() and approval() return afterwards; a later one replaces it", () => {
  const l = windowLink(() => {});
  l.take({ kind: "context", context: CONTEXT, approval: APPROVAL });
  assert.deepEqual(l.context(), CONTEXT);
  assert.deepEqual(l.approval(), APPROVAL);
  l.take({ kind: "context", context: { ...CONTEXT, quiet: true }, approval: null });
  assert.equal(l.context().quiet, true);
  assert.equal(l.approval(), null);
});

test("decide, release and session send the three shapes of the brief, and nothing else", () => {
  const { sent, send } = sender();
  const l = windowLink(send);
  l.decide("allow", "r1");
  l.decide("deny", "r2");
  l.release("s1");
  l.release();
  l.session("s2", null);
  l.session("s3", "s2");
  assert.deepEqual(sent, [
    { kind: "decide", decision: "allow", requestId: "r1" },
    { kind: "decide", decision: "deny", requestId: "r2" },
    { kind: "release", sessionId: "s1" },
    { kind: "release", sessionId: undefined },
    { kind: "session", id: "s2", retired: null },
    { kind: "session", id: "s3", retired: "s2" },
  ]);
});

test("the window ignores a message that is not a well-formed context: the last good one stays", () => {
  const l = windowLink(() => {});
  l.take({ kind: "context", context: CONTEXT, approval: null });
  const bad = [
    null, 7, "context", [], {},
    { kind: "decide", decision: "allow", requestId: "r" },
    { kind: "context", context: null, approval: null },
    { kind: "context", context: { rightNow: 3, quiet: false, mood: "idle" }, approval: null },
    { kind: "context", context: { rightNow: "x", quiet: "no", mood: "idle" }, approval: null },
    { kind: "context", context: { rightNow: "x", quiet: false, mood: {} }, approval: null },
    { kind: "context", context: { ...CONTEXT, rightNow: "x".repeat(5000) }, approval: null },
  ];
  for (const m of bad) {
    assert.equal(checkToWindow(m), null, JSON.stringify(m)?.slice(0, 80));
    l.take(m);
    assert.deepEqual(l.context(), CONTEXT);
  }
});

test("an approval that is not clean is dropped alone: the context is kept", () => {
  const odd = [
    "allow", 7, [], {},
    { ...APPROVAL, requestId: "" }, // an empty id (a hook without one)
    { ...APPROVAL, sessionId: "" },
    { ...APPROVAL, requestId: 1 },
    { requestId: "r", sessionId: "s", tool: "t" },
    { ...APPROVAL, requestId: "r".repeat(500) },
    { ...APPROVAL, command: "c".repeat(4001) },
  ];
  for (const approval of odd) {
    const l = windowLink(() => {});
    l.take({ kind: "context", context: { ...CONTEXT, quiet: true }, approval: APPROVAL });
    l.take({ kind: "context", context: CONTEXT, approval });
    assert.deepEqual(l.context(), CONTEXT, JSON.stringify(approval)?.slice(0, 60));
    assert.equal(l.approval(), null);
    assert.deepEqual(checkToWindow({ kind: "context", context: CONTEXT, approval }), { kind: "context", context: CONTEXT, approval: null });
  }
  // A command at the limit is kept.
  const edge = { ...APPROVAL, command: "c".repeat(4000) };
  assert.deepEqual(checkToWindow({ kind: "context", context: CONTEXT, approval: edge }).approval, edge);
});

test("a context keeps only its known fields (an extra key on the wire is dropped)", () => {
  const l = windowLink(() => {});
  l.take({ kind: "context", context: { ...CONTEXT, extra: "x" }, approval: { ...APPROVAL, extra: "y" }, more: 1 });
  assert.deepEqual(l.context(), CONTEXT);
  assert.deepEqual(l.approval(), APPROVAL);
});

// ── what the island accepts from the window ──────────────────────────────────

const ID = "0a1b2c3d-1111-4222-8333-444455556666";

function islandLinkRecorder() {
  const calls = [];
  return {
    calls,
    context: () => CONTEXT,
    approval: () => null,
    decide: (d, r) => calls.push(["decide", d, r]),
    release: (s) => calls.push(["release", s]),
    session: (id, retired) => calls.push(["session", id, retired]),
  };
}

test("checkToIsland takes the four kinds and refuses a wrong shape, a long id and an id that breaks the conversation-id rule", () => {
  assert.deepEqual(checkToIsland({ kind: "decide", decision: "allow", requestId: "r1" }), { kind: "decide", decision: "allow", requestId: "r1" });
  assert.deepEqual(checkToIsland({ kind: "release", sessionId: "s" }), { kind: "release", sessionId: "s" });
  assert.deepEqual(checkToIsland({ kind: "release" }), { kind: "release", sessionId: undefined });
  assert.deepEqual(checkToIsland({ kind: "session", id: "s", retired: null }), { kind: "session", id: "s", retired: null });
  assert.deepEqual(checkToIsland({ kind: "current", id: ID }), { kind: "current", id: ID });
  const bad = [
    null, undefined, 3, "decide", [], {}, { kind: "nope" },
    { kind: "decide", decision: "ask", requestId: "r" },
    { kind: "decide", decision: "allow", requestId: "" },
    { kind: "decide", decision: "allow", requestId: 4 },
    { kind: "decide", decision: "allow", requestId: "r".repeat(300) },
    { kind: "release", sessionId: 5 },
    { kind: "release", sessionId: "s".repeat(300) },
    { kind: "session", id: "", retired: null },
    { kind: "session", id: "s".repeat(300), retired: null },
    { kind: "session", id: "s", retired: 4 },
    { kind: "current", id: "" },
    { kind: "current", id: "../x" },
    { kind: "current", id: "A" },
    { kind: "current", id: "-a" },
    { kind: "current", id: "a".repeat(65) },
    { kind: "current", id: null },
    { kind: "current" },
  ];
  for (const m of bad) assert.equal(checkToIsland(m), null, JSON.stringify(m));
});

test("the island acts on a window message only while the chat is popped out", () => {
  const l = islandLinkRecorder();
  State.chatPoppedOut = false;
  State.chatId = null;
  for (const m of [
    { kind: "decide", decision: "allow", requestId: "r1" },
    { kind: "release", sessionId: "s1" },
    { kind: "session", id: "s1", retired: null },
    { kind: "current", id: ID },
  ]) applyToIsland(m, l);
  assert.deepEqual(l.calls, []);
  assert.equal(State.chatId, null);
});

test("while popped out: decide, release and session go to the island's link, current sets the conversation's id", () => {
  const l = islandLinkRecorder();
  State.chatPoppedOut = true;
  State.chatId = null;
  applyToIsland({ kind: "decide", decision: "deny", requestId: "r1" }, l);
  applyToIsland({ kind: "release", sessionId: "s1" }, l);
  applyToIsland({ kind: "session", id: "s2", retired: "s1" }, l);
  applyToIsland({ kind: "current", id: ID }, l);
  assert.deepEqual(l.calls, [["decide", "deny", "r1"], ["release", "s1"], ["session", "s2", "s1"]]);
  assert.equal(State.chatId, ID);
  State.chatPoppedOut = false;
  State.chatId = null;
});

test("a malformed message while popped out changes nothing", () => {
  const l = islandLinkRecorder();
  State.chatPoppedOut = true;
  State.chatId = "keep";
  for (const m of [null, "x", { kind: "current", id: "Bad Id" }, { kind: "decide", decision: "allow" }, { kind: "session", id: 1 }]) applyToIsland(m, l);
  assert.deepEqual(l.calls, []);
  assert.equal(State.chatId, "keep");
  State.chatPoppedOut = false;
  State.chatId = null;
});

test("State.chatPoppedOut starts false", () => {
  assert.match(state, /chatPoppedOut = false;/);
});

// ── Rust: the window, its commands and the relay ─────────────────────────────

test("lib.rs builds the chat window once, right after the settings window and before the island's page", () => {
  assert.equal(lib.split("create_chat_window(&handle);").length - 1, 1);
  assert.match(lib, /create_settings_window\(&handle\);\s*create_chat_window\(&handle\);/);
  assert.ok(lib.indexOf("create_chat_window(&handle);") < lib.indexOf("desktop::create_window(&handle);"));
  const at = lib.indexOf("fn create_chat_window");
  const body = lib.slice(at, lib.indexOf("\npub fn show_settings_window", at) > at ? lib.indexOf("\npub fn show_settings_window", at) : at + 2500);
  assert.match(body, /WebviewWindowBuilder::new\(app, CHAT_LABEL, url\)/);
  assert.match(body, /\.title\("Chat — NotchMeow"\)/);
  assert.match(body, /\.inner_size\(520\.0, 640\.0\)/);
  assert.match(body, /\.min_inner_size\(420\.0, 360\.0\)/);
  assert.match(body, /\.resizable\(true\)/);
  assert.match(body, /\.visible\(false\)/);
  assert.match(body, /\.center\(\)/);
  assert.match(body, /\.additional_browser_args\(BROWSER_ARGS\)/);
  assert.match(lib, /fn chat_page_url\(app: &AppHandle\) -> WebviewUrl/);
  assert.match(lib, /"\/chat\.html"/);
  assert.match(lib, /WebviewUrl::App\("chat\.html"\.into\(\)\)/);
});

test("closing the chat window only hides it: prevent_close, hide, and the island is told", () => {
  const at = lib.indexOf("fn create_chat_window");
  const body = lib.slice(at, at + 2500);
  assert.match(body, /CloseRequested/);
  assert.match(body, /api\.prevent_close\(\)/);
  assert.match(body, /\.hide\(\)/);
  assert.match(body, /chat_hidden\(&app\)|"chat-window-hidden"/);
});

test("the three commands exist, are registered, and use the frozen event names through logged_emit", () => {
  for (const name of ["show_chat_window", "hide_chat_window", "chat_relay"]) {
    assert.match(lib, new RegExp(`fn ${name}\\(`));
    assert.match(lib, new RegExp(`\\n\\s+${name},`), `${name} is in the invoke handler`);
  }
  assert.match(lib, /logged_emit\("chat-window-open"/);
  assert.match(lib, /logged_emit\("chat-window-hidden"/);
  assert.match(lib, /logged_emit\("chat-msg"/);
  assert.match(lib, /emit_to\(CHAT_LABEL, "chat-window-open"/);
  assert.match(lib, /emit_to\(island::WINDOW_LABEL, "chat-window-hidden"/);
  assert.match(lib, /"conversationId"/);
});

test("the relay's target and the shown conversation's id are checked in Rust (pure functions, tested there)", () => {
  assert.match(lib, /fn chat_target\(to: &str\) -> Option<&'static str>/);
  assert.match(lib, /fn chat_open_id\(id: Option<String>\) -> Option<String>/);
  assert.match(lib, /companion_store::is_id/);
  const relay = lib.slice(lib.indexOf("fn chat_relay("));
  assert.match(relay.slice(0, 600), /chat_target\(&to\)/);
});

test("no log line in the chat window's Rust names a message, an id or a path", () => {
  const at = libRaw.indexOf("// ── Chat window");
  assert.ok(at > 0, "the section is marked");
  const section = lib.slice(at, lib.indexOf("pub fn run()", at));
  assert.ok(section.includes("log::line("), "the section logs something");
  for (const m of section.matchAll(/log::line\(([^\n]*)\)/g)) assert.doesNotMatch(m[1].replace("{err}", ""), /\{|msg|conversation|id\b/, m[1]); // {err} is the window builder's own error, as for the settings window
});

test("open_url refuses a hostile address in Rust the way the page's link filter does", () => {
  assert.match(lib, /fn url_ok\(url: &str\) -> bool/);
  const at = lib.indexOf("fn open_url(url: String)");
  assert.match(lib.slice(at, at + 200), /!url_ok\(&url\)/);
});

test("the chat window may use the app's commands and events as the other two do", () => {
  const c = JSON.parse(caps);
  assert.deepEqual(c.windows, ["island", "settings", "chat"]);
});

test("vite builds chat.html as a third page after the desktop one", () => {
  assert.match(vite, /desktop: resolve\(__dirname, "desktop\.html"\),\s*chat: resolve\(__dirname, "chat\.html"\),/);
  const html = rawText("chat.html");
  assert.match(html, /<title>Chat — NotchMeow<\/title>/);
  assert.match(html, /src="\/src\/chatwin\/main\.ts"/);
});

// ── The pages ────────────────────────────────────────────────────────────────

test("the window page does nothing on its own: no timer, no frame callback", () => {
  assert.doesNotMatch(win, /setInterval|setTimeout|requestAnimationFrame/);
});

test("the window page listens to the events of the brief and nothing else (companion-deleted-all: fix round 1)", () => {
  const listened = [...win.matchAll(/onEvent<[^>]*>\("([a-z-]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(listened, ["chat-msg", "chat-window-open", "companion-deleted-all", "settings-changed"]);
  assert.match(win, /Bridge\.boot\(\)/);
  assert.match(win, /buildPrompt\(\{ openSettingsWindow: [^}]*openUrl: [^}]*emote: \(\) => \{\} \}, \(\) => \{\}, link\)/);
  assert.match(win, /Bridge\.chatRelay\("island", \{ kind: "current"/);
  assert.match(win, /openConversation\(bridgeStore, /);
  assert.match(win, /startNewChat\(/);
});

test("the window loads what it is told to open from its file, whatever it held, and a bad id or file is a new chat", () => {
  const at = win.indexOf("open = (asked) =>");
  const body = win.slice(at, at + 700);
  assert.match(body, /!isConversationId\(asked\)\) startNewChat\(link, bridgeChat\);\s*else if \(!\(await openConversation\(bridgeStore, asked, link, bridgeChat\)\)\) \{\s*startNewChat\(link, bridgeChat\);\s*noteInChat\(OPEN_FAILED_NOTE\);/);
  // No "same id, keep what is here" shortcut: a hidden window's page may hold an older copy of the conversation the island has moved on.
  assert.doesNotMatch(body, /State\.chatId/);
});

test("Rust tells the window to open only when it was hidden: a window already showing is only brought forward", () => {
  const at = lib.indexOf("fn show_chat_window(");
  const body = lib.slice(at, at + 1200);
  const seen = body.indexOf("let was_showing = win.is_visible()");
  const shown = body.indexOf("win.show()");
  const emit = body.indexOf('"chat-window-open"');
  assert.ok(seen > 0 && shown > seen && emit > shown, "visibility is read before the window is shown, and the event comes after");
  assert.match(body, /if !was_showing \{\s*logged_emit\("chat-window-open"/);
});

test("the window's relay listeners are registered before boot, and a first open is kept until the chat is mounted", () => {
  const boot = win.indexOf("await Bridge.boot()");
  const open = win.indexOf('onEvent<{ conversationId?: unknown }>("chat-window-open"');
  const msg = win.indexOf('onEvent<unknown>("chat-msg"');
  assert.ok(boot > 0 && open > 0 && msg > 0);
  assert.ok(open < boot && msg < boot, "both listeners come before the first await of boot");
  assert.match(win, /else early = \{ asked: p\?\.conversationId \}/);
  assert.match(win, /if \(early\) open\(/);
  // The settings listener needs boot's settings and may come after; nothing else is awaited before the two.
  assert.ok(win.indexOf("await", win.indexOf("async function main")) === win.indexOf("await onEvent", win.indexOf("async function main")), "the first await in main is a listener");
});

test("a page with no Sidekick (the window) never sends a status question to a model: a note, and the field keeps its text", () => {
  // The rule the guard asks of: the chip's own question and its short forms are status questions.
  for (const q of ["What's Claude doing?", "what is claude doing", "What's Claude doing"]) assert.equal(matchStatusQuestion(q).matched, true, q);
  assert.equal(matchStatusQuestion("Explain this stack trace to me please").matched, false);
  const at = chat.indexOf("  async function submit() {");
  const body = chat.slice(at, chat.indexOf("  function continueOrRetry", at));
  const guard = body.indexOf("if (!Hub.sk && matchStatusQuestion(text).matched) {");
  const clear = body.indexOf('input.value = "";');
  const local = body.indexOf("if (answerLocally(text)) return;");
  const ask = body.indexOf("void ask(");
  assert.ok(guard > 0 && clear > guard, "the guard is before the field is cleared, so the text stays");
  assert.ok(local > clear && ask > local, "the island's path (Hub.sk set) is the same as before: answerLocally, then the model");
  const g = body.slice(guard, clear);
  assert.match(g, /note\(STATUS_IN_ISLAND_NOTE\);/);
  assert.match(g, /return;/);
  assert.doesNotMatch(g, /ask\(|Bridge\.aiChat|input\.value/);
  // The only call to the model's stream is inside ask, and ask is reached through submit (after the guard) and the retry buttons (fixed words).
  assert.equal(chat.split("Bridge.aiChat(").length - 1, 1);
  // The window's page has no Sidekick: Hub.sk is assigned only by the island's main.ts.
  assert.doesNotMatch(win, /Hub\.sk|sidekick/i);
  assert.match(main, /Hub\.sk = new Sidekick\(/);
  assert.match(code("companion/chrome.ts"), /STATUS_IN_ISLAND_NOTE = "Ask this in the island — the window can't see your sessions\."/);
});

test("the island pushes the context only while popped out, only when it changed, and only through chat_relay to the window", () => {
  assert.match(main, /if \(!State\.chatPoppedOut\) \{[^}]*lastChatContext = "";[^}]*return;[^}]*\}/);
  assert.match(main, /const msg = \{ kind: "context", context: State\.contextNow\(\), approval: State\.chatApprovals\.front \};/);
  assert.match(main, /Bridge\.chatRelay\("chat", msg\)/);
  assert.match(main, /text === lastChatContext/);
  // The push is inside the State.notify subscriber and nowhere else.
  assert.equal(main.split('Bridge.chatRelay("chat"').length - 1, 1);
  assert.doesNotMatch(main, /chatRelay[\s\S]{0,80}setInterval/);
});

test("the island listens to the window's messages and its hiding, and takes the chat back only if it was out", () => {
  assert.match(main, /onEvent<unknown>\("chat-msg", \(raw\) => applyToIsland\(raw, islandLink\(\)\)\)/);
  assert.match(main, /onEvent<null>\("chat-window-hidden"/);
  const at = main.indexOf('"chat-window-hidden"');
  const body = main.slice(at, at + 1000);
  assert.match(body, /if \(!State\.chatPoppedOut\) return;/);
  assert.match(body, /State\.chatPoppedOut = false;/);
  // The conversation is read again from its file; none saved, or one that cannot be opened, is a new chat (the shared Rust session holds the window's turns).
  assert.match(body, /if \(State\.chatId === null\) startNewChat\(islandLink\(\), bridgeChat\);\s*else if \(!\(await openConversation\(bridgeStore, State\.chatId, islandLink\(\), bridgeChat\)\)\) \{\s*startNewChat\(islandLink\(\), bridgeChat\);\s*noteInChat\(OPEN_FAILED_NOTE\);/);
});

test("a drop while popped out hides the window before the reset", () => {
  const at = island.indexOf("private swallow(");
  const body = island.slice(at, island.indexOf("UploadSeq.performDrop", at));
  const hide = body.indexOf("Bridge.hideChatWindow()");
  const reset = body.indexOf("Bridge.chatReset()");
  assert.ok(hide > 0 && reset > 0, "both are in swallow");
  assert.ok(hide < reset, "the window is hidden first");
  assert.match(body, /if \(State\.chatPoppedOut\) \{[^}]*Bridge\.hideChatWindow\(\)[^}]*State\.chatPoppedOut = false;/);
  // The drop's own file is set on the island's state, after nothing that forgets it: startNewChat (which forgets the drop) is not called here.
  assert.doesNotMatch(body, /startNewChat\(/);
  assert.ok(body.indexOf("State.droppedFile = { name, path };") > 0);
});

test("the pop-out: save first, then out, then the window, then the island folds; it is off while a reply streams", () => {
  const at = chat.indexOf("async function popOut()");
  assert.ok(at > 0, "popOut is in chat.ts");
  const body = chat.slice(at, at + 1200);
  assert.match(body, /if \(sending\) return;/);
  const save = body.indexOf("saveCurrent(");
  const out = body.indexOf("State.chatPoppedOut = true;");
  const show = body.indexOf("Bridge.showChatWindow(State.chatId)");
  const fold = body.indexOf("actions.collapse?.()");
  assert.ok(save > 0 && out > save && show > out && fold > show, "save, popped, show, collapse");
  assert.match(chat, /popOutItem\.toggleAttribute\("disabled", sending\)/);
  // Only the island offers it: the window's actions have no collapse.
  assert.match(chat, /if \(actions\.collapse\) menu\.append\(popOutItem\)/);
});

test("the island's chat shows only the note and Bring it back while popped out", () => {
  assert.match(chat, /POPPED_OUT_NOTE/);
  assert.match(chat, /text: BRING_BACK, onclick: \(\) => void Bridge\.hideChatWindow\(\)/);
  assert.match(chat, /State\.chatPoppedOut/);
});

test("the chat tab brings the window forward while popped out", () => {
  const at = views.indexOf("const tabChat");
  const line = views.slice(at, at + 400);
  assert.match(line, /State\.chatPoppedOut/);
  assert.match(views, /Bridge\.showChatWindow\(State\.chatId\)/);
});

test("Bridge has the three commands, the window has no way to reach the island's approvals except the relay", () => {
  assert.match(bridge, /showChatWindow: /);
  assert.match(bridge, /"show_chat_window", \{ conversationId \}/);
  assert.match(bridge, /hideChatWindow: /);
  assert.match(bridge, /"hide_chat_window"/);
  assert.match(bridge, /chatRelay: \(to: "island" \| "chat", msg: unknown\)/);
  assert.match(bridge, /"chat_relay", \{ to, msg \}/);
  assert.doesNotMatch(win, /island\/hooks|chatApprovals|decideChatApproval|releaseChatApprovals|claudeSessions/);
});

test("link.ts re-exports windowLink, and windowlink.ts never logs a message", () => {
  assert.match(link, /export \{ windowLink \} from "\.\/windowlink\.ts";/);
  const wl = code("companion/windowlink.ts");
  assert.doesNotMatch(wl, /console\./);
  assert.doesNotMatch(win, /console\.(log|info|debug)/);
});
