import test from "node:test";
import assert from "node:assert/strict";
import { code } from "../projects-tests/util.mjs";

// The companion's turn in the app (F3a-tauri, Task 5): the chat asks the link for the approval, the chat's system text comes from
// systemFor, the Projects view and the state feed it, and the Rust commands it calls are the frozen names. Comments are blanked first.

const chat = code("views/chat.ts"), views = code("views/views.ts"), link = code("companion/link.ts"), turn = code("companion/turn.ts");
const model = code("projects/model.ts"), state = code("core/state.ts"), bridge = code("core/bridge.ts");

test("chat.ts reaches the island's approvals and sessions only through its link, never through island/hooks", () => {
  assert.doesNotMatch(chat, /from "\.\.\/island\/hooks"/);
  assert.doesNotMatch(chat, /State\.chatApprovals|State\.claudeSessions|decideChatApproval|releaseChatApprovals/);
  assert.match(chat, /link\.approval\(\)/);
  assert.match(chat, /link\.decide\(/);
  assert.match(chat, /link\.release\(\)/);
  assert.match(chat, /link\.session\(/);
});

test("the approval card reads the link, and the link is built from the island's own state and hooks", () => {
  assert.match(link, /export function islandLink\(\): ChatLink/);
  assert.match(link, /State\.chatApprovals\.front/);
  assert.match(link, /decideChatApproval\(/);
  assert.match(link, /releaseChatApprovals\(/);
  assert.match(link, /State\.contextNow\(\)/);
});

test("every turn is given the companion's text once, through systemFor, and it is sent as Bridge.aiChat's system argument", () => {
  assert.equal(chat.split("systemFor(").length - 1, 1, "systemFor is called once in chat.ts");
  assert.match(chat, /req\.system \?\? systemFor\(link\.context\(\), State\.settings, localDay\(new Date\(\)\)\)/);
  assert.match(chat, /Bridge\.aiChat\(req\.feature, req\.text, req\.attachments, req\.regenerate, system, req\.quick === true, onEvent\)/);
});

test("the companion's text is built before the thinking override, so the mood read is the Main cat's own", () => {
  const start = chat.indexOf("async function ask(req: Ask)");
  assert.ok(start > 0, "ask is found");
  const body = chat.slice(start, chat.indexOf("  function answerLocally", start));
  const sysAt = body.indexOf("systemFor(");
  const thinkingAt = body.indexOf('State.stateOverride = "thinking"');
  assert.ok(sysAt > 0 && thinkingAt > 0, "both are in ask");
  assert.ok(sysAt < thinkingAt, "systemFor reads effectiveState before the override is set");
});

test("the cloud line is written once per provider, before the send, and kept in the settings", () => {
  const at = chat.indexOf("cloudLine(resolution, State.settings.companion)");
  assert.ok(at > 0, "the line is asked for with the chip's resolution");
  assert.ok(chat.indexOf("void ask({ text, attachments, feature, regenerate: false, retries: 0 });") > at);
  assert.match(chat, /State\.settings\.companion\.cloudNoticeShown = notice\.shown;/);
});

test("buildViews hands the chat the island's link, and the chat keeps the actions it had", () => {
  assert.match(views, /buildPrompt\(actions, onChatHeightChange, islandLink\(\)\)/);
  assert.match(views, /import \{ islandLink \} from "\.\.\/companion\/link\.ts";/);
  assert.match(chat, /export function buildPrompt\(actions: ChatActions, onHeightChange: \(\) => void, link: ChatLink\): ViewHost/);
});

test("the turn rules hold the page's settings only: no account name, device pc, no memory, no timer", () => {
  assert.match(turn, /device: "pc"|device: 'pc'/);
  assert.match(turn, /useMemory: false/);
  assert.doesNotMatch(turn, /userName\s*:/);
  assert.doesNotMatch(turn, /setInterval|setTimeout|requestAnimationFrame/);
});

test("the Projects model has a view() that is only the registry's view, and the state's context reads it", () => {
  assert.match(model, /view\(\): ProjectsView \{\s*return projectsView\(this\.reg, this\.now\(\), \{ steps: Object\.fromEntries\(this\.steps\) \}\);/);
  assert.match(state, /contextNow\(\): TurnContext/);
  assert.match(state, /view: this\.projects\.view\(\), attention: this\.attentionNeeded, mood: this\.effectiveState/);
});

test("the bridge sends the system text and the loaded turns, and reads the last text sent, by the frozen command names", () => {
  assert.match(bridge, /aiChat: \([\s\S]*?system: string,[\s\S]*?onEvent: \(event: AiEvent\) => void,?\s*\)/);
  assert.match(bridge, /callOrThrow<void>\("ai_chat", \{ feature, text, attachments, regenerate, system, quick, onEvent: channel \}\)/);
  assert.match(bridge, /aiLoadTurns: .*"ai_load_turns"/);
  assert.match(bridge, /companionLastSent: .*"companion_last_sent"/);
});

// Delete all in Settings (or the chat pane's own) empties what the companion last sent and tells every window, so each open chat forgets its id (F3a-tauri, fix round 1).
const lib = code("../src-tauri/src/lib.rs"), mainPage = code("main.ts"), chatWin = code("chatwin/main.ts"), aiMod = code("../src-tauri/src/ai/mod.rs");

test("companion_delete_all clears what the companion last sent and emits companion-deleted-all to every window", () => {
  const body = lib.slice(lib.indexOf("async fn companion_delete_all("), lib.indexOf("/// Lets the island write", lib.indexOf("async fn companion_delete_all(")));
  assert.match(body, /ai::forget_sent\(&ai\.sent\)/);
  assert.match(body, /app\.emit\("companion-deleted-all", \(\)\)/, "broadcast with app.emit, not emit_to");
  assert.match(body, /companion_store::announces\(removed\)/, "announced when a file went, even when the rest failed");
  assert.match(aiMod, /pub fn forget_sent\(sent: &Mutex<Vec<String>>\)/);
});

test("the island page and the pop-out chat window both forget the open chat on companion-deleted-all", () => {
  assert.match(mainPage, /onEvent<unknown>\("companion-deleted-all", \(\) => forgetDeletedAll\(islandLink\(\), bridgeChat\)\)/);
  assert.match(chatWin, /onEvent<unknown>\("companion-deleted-all", \(\) => forgetDeletedAll\(link, bridgeChat\)\)/);
});
