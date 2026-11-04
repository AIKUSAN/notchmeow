import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { code } from "../projects-tests/util.mjs";
import { State } from "../../src/core/state.ts";
import { CONVERSATIONS_MAX, titleOf } from "../../src/companion/core.ts";
import {
  nextMessageId,
  openConversation,
  removeAll,
  removeOne,
  rename,
  saveCurrent,
  startNewChat,
  togglePin,
  forgetDeletedAll,
  noteInChat,
} from "../../src/companion/session.ts";
import { recordOf } from "../../src/companion/store.ts";

// The chat's saved conversations (F3a-tauri, Task 6): the files are an in-memory StoreBackend here, the chat's backend and link are recorders. The
// view (views/chat.ts) is a DOM and is pinned by source reads at the end of this file.

function memoryStore() {
  const files = new Map();
  return {
    files,
    async list() {
      return [...files.values()].map((r) => ({ id: r.id, title: r.title, pinned: r.pinned, updatedAt: r.updatedAt }));
    },
    async load(id) {
      return files.get(id) ?? null;
    },
    async save(rec) {
      files.set(rec.id, rec);
      return true;
    },
    async remove(id) {
      return files.delete(id);
    },
    async removeAll() {
      files.clear();
      return true;
    },
  };
}

function recorder() {
  return { resets: 0, loaded: null, reset() { this.resets++; }, loadTurns(t) { this.loaded = t; } };
}

function linkRecorder() {
  return { released: 0, context: () => ({}), approval: () => null, decide() {}, release() { this.released++; }, session() {} };
}

/** The chat's state back to a new chat with nothing in it (the State is shared by every test in this file). */
function fresh() {
  State.chatHistory = [];
  State.localAnswers = [];
  State.pendingAttachment = null;
  State.droppedFile = null;
  State.promptContext = null;
  State.dropReader = null;
  State.chatEpoch = 0;
  State.chatId = null;
  State.chatTitle = null;
  State.chatPinned = false;
  State.chatCreatedAt = 0;
  State.claudeLevel = { level: "chat", folder: null };
  State.claudeSessions.clear();
}

const user = (id, content, attachments) => ({ id, role: "user", content, ...(attachments ? { attachments } : {}) });
const reply = (id, content) => ({ id, role: "assistant", content });
const rec = (id, pinned, updatedAt) => ({ version: 1, id, title: "t", pinned, createdAt: 1, updatedAt, messages: [] });

test("a first save gives the conversation an id and its first message's title", async () => {
  fresh();
  const store = memoryStore();
  State.chatHistory = [user(1, "Explain the notch layout please"), reply(2, "Sure.")];
  assert.equal(await saveCurrent(store, 100), true);
  assert.match(State.chatId, /^[a-z0-9][a-z0-9-]{0,63}$/);
  assert.equal(State.chatCreatedAt, 100);
  const saved = store.files.get(State.chatId);
  assert.equal(saved.title, titleOf("Explain the notch layout please"));
  assert.deepEqual(saved.messages.map((m) => m.role), ["user", "assistant"]);
});

test("a second save keeps the id and createdAt, and a chat with no user message is not saved", async () => {
  fresh();
  const store = memoryStore();
  State.chatHistory = [reply(1, "hello")];
  assert.equal(await saveCurrent(store, 1), false);
  assert.equal(State.chatId, null);
  assert.equal(store.files.size, 0);
  State.chatHistory = [user(2, "hi"), reply(3, "yo")];
  assert.equal(await saveCurrent(store, 100), true);
  const id = State.chatId;
  State.chatHistory.push(user(4, "more"), reply(5, "ok"));
  assert.equal(await saveCurrent(store, 200), true);
  assert.equal(State.chatId, id);
  assert.equal(State.chatCreatedAt, 100);
  assert.equal(store.files.get(id).createdAt, 100);
  assert.equal(store.files.get(id).updatedAt, 200);
  assert.equal(store.files.size, 1);
});

test("opening a conversation releases the chat's approvals and resets Claude", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "Hi there"), reply(2, "Hello!")];
  await saveCurrent(store, 10);
  const id = State.chatId;
  fresh();
  State.claudeLevel = { level: "agent", folder: "C:\\dev\\app" };
  State.claudeSessions.add("session-a");
  assert.equal(await openConversation(store, id, link, chat), true);
  assert.equal(link.released, 1);
  assert.equal(State.claudeLevel.level, "chat");
  assert.equal(State.claudeSessions.size, 0);
  assert.equal(chat.resets, 1);
  assert.deepEqual(chat.loaded, [{ role: "user", text: "Hi there" }, { role: "assistant", text: "Hello!" }]);
  assert.equal(State.chatId, id);
  assert.deepEqual(State.chatHistory.map((m) => [m.role, m.content]), [["user", "Hi there"], ["assistant", "Hello!"]]);
});

test("a record that does not clean is not opened, and nothing changes", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  store.files.set("junk", { id: "Bad", messages: [] });
  State.chatHistory = [user(1, "keep me")];
  State.chatId = "still-here";
  const before = State.chatHistory;
  assert.equal(await openConversation(store, "junk", link, chat), false);
  assert.equal(await openConversation(store, "missing", link, chat), false);
  assert.equal(State.chatHistory, before);
  assert.equal(State.chatId, "still-here");
  assert.equal(link.released, 0);
  assert.equal(chat.resets, 0);
  assert.equal(chat.loaded, null);
});

test("a save after a reset never writes the old turns under the new id", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "first"), reply(2, "answer")];
  await saveCurrent(store, 1);
  const oldId = State.chatId;
  startNewChat(link, chat);
  State.chatHistory.push(user(3, "second"));
  await saveCurrent(store, 2);
  assert.equal(store.files.size, 2);
  const fresher = store.files.get(State.chatId);
  assert.notEqual(State.chatId, oldId);
  assert.equal(fresher.messages.length, 1);
  assert.equal(fresher.messages[0].text, "second");
  assert.equal(store.files.get(oldId).messages.length, 2);
});

test("rename goes through titleOf, for the open conversation and for one in the list", async () => {
  fresh();
  const store = memoryStore();
  State.chatHistory = [user(1, "hi"), reply(2, "yo")];
  await saveCurrent(store, 1);
  const openId = State.chatId;
  assert.equal(await rename(store, openId, "  x".repeat(30), 5), true);
  const title = store.files.get(openId).title;
  assert.equal(title, titleOf("  x".repeat(30)));
  assert.equal([...title].length, 40);
  assert.equal(State.chatTitle, titleOf("  x".repeat(30)));

  store.files.set("other", rec("other", false, 7));
  assert.equal(await rename(store, "other", "Plans", 9), true);
  assert.equal(store.files.get("other").title, "Plans");
  assert.equal(store.files.get("other").updatedAt, 7, "a row that is not open keeps its place in the list");
  assert.equal(State.chatId, openId, "renaming another conversation leaves the open one alone");
});

test("delete all empties the list and starts a new chat when the open one was in it", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "a"), reply(2, "b")];
  await saveCurrent(store, 1);
  assert.equal(await removeAll(store, link, chat), true);
  assert.equal(store.files.size, 0);
  assert.equal(State.chatId, null);
  assert.deepEqual(State.chatHistory, []);
  assert.equal(chat.resets, 1);
});

test("delete all keeps an open chat that is not saved yet", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  store.files.set("other", rec("other", false, 1));
  State.chatHistory = [user(1, "draft")];
  assert.equal(await removeAll(store, link, chat), true);
  assert.equal(store.files.size, 0);
  assert.equal(State.chatHistory.length, 1);
  assert.equal(chat.resets, 0);
});

test("deleting the open conversation starts a new chat, so its next reply cannot bring it back", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "a"), reply(2, "b")];
  await saveCurrent(store, 1);
  const openId = State.chatId;
  store.files.set("other", rec("other", false, 1));
  assert.equal(await removeOne(store, "other", link, chat), true);
  assert.equal(State.chatId, openId, "another conversation's delete leaves the open one");
  assert.equal(chat.resets, 0);
  assert.equal(await removeOne(store, openId, link, chat), true);
  assert.equal(State.chatId, null);
  assert.equal(chat.resets, 1);
});

test("a 50th pin is refused: at most 49 conversations are pinned, and an unpin is always allowed", async () => {
  fresh();
  const store = memoryStore();
  for (let i = 0; i < 48; i++) store.files.set(`p${i}`, rec(`p${i}`, true, i));
  store.files.set("u1", rec("u1", false, 100));
  store.files.set("u2", rec("u2", false, 101));
  assert.equal(CONVERSATIONS_MAX, 50);
  assert.equal(await togglePin(store, "u1", 200), "pinned", "the 49th pin");
  assert.equal(await togglePin(store, "u2", 201), "full", "the 50th is refused");
  assert.equal(store.files.get("u2").pinned, false);
  assert.equal(await togglePin(store, "p0", 202), "unpinned");
  assert.equal(await togglePin(store, "u2", 203), "pinned", "a seat is free again");
});

test("with 49 pinned, a new conversation is kept and an old unpinned one goes, so no pin is evicted", async () => {
  fresh();
  const store = memoryStore();
  for (let i = 0; i < 49; i++) store.files.set(`p${i}`, rec(`p${i}`, true, i));
  store.files.set("old", rec("old", false, 1000));
  State.chatHistory = [user(1, "new one")];
  assert.equal(await saveCurrent(store, 2000), true);
  assert.equal(store.files.size, 50);
  assert.ok(store.files.has(State.chatId));
  assert.ok(!store.files.has("old"));
  for (let i = 0; i < 49; i++) assert.ok(store.files.has(`p${i}`));
});

test("the open chat's pin is kept with its file and survives a drop", async () => {
  fresh();
  const store = memoryStore();
  State.chatHistory = [user(1, "pin me"), reply(2, "ok")];
  await saveCurrent(store, 1);
  const openId = State.chatId;
  assert.equal(await togglePin(store, openId, 2), "pinned");
  assert.equal(store.files.get(openId).pinned, true);
  // A drop: the island clears the id. The next first save is a new conversation with no title or pin of the old one.
  State.chatId = null;
  State.chatHistory = [user(3, "fresh")];
  await saveCurrent(store, 3);
  assert.notEqual(State.chatId, openId);
  assert.equal(State.chatPinned, false);
  assert.equal(store.files.get(State.chatId).pinned, false);
  assert.equal(store.files.get(State.chatId).title, titleOf("fresh"));
});

test("restored messages take ids the chat has not used, and their file names stay names", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  store.files.set("withfiles", {
    version: 1, id: "withfiles", title: "Files", pinned: false, createdAt: 1, updatedAt: 2,
    messages: [{ role: "user", text: "look", caption: "", files: ["a.png"] }, { role: "assistant", text: "ok", caption: "", files: [] }],
  });
  assert.equal(await openConversation(store, "withfiles", link, chat), true);
  assert.deepEqual(State.chatHistory[0].attachments, ["a.png"]);
  assert.equal(State.pendingAttachment, null, "a restored file is not a pending attachment: nothing sends it");
  const ids = State.chatHistory.map((m) => m.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.ok(!ids.includes(nextMessageId()), "the chat's next id is new");
  assert.notEqual(nextMessageId(), nextMessageId());
});

test("a new chat forgets the dropped file: its chip, its context and the file waiting for a send are cleared, and so is an opened one's", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  const dropped = { name: "a.png", path: "C:\\dev\\inbox\\a.png" };
  State.droppedFile = dropped;
  State.promptContext = { kind: "file", name: "a.png", path: "C:\\dev\\inbox\\a.png" };
  State.dropReader = "Claude";
  State.pendingAttachment = dropped.path;
  startNewChat(link, chat);
  assert.equal(State.droppedFile, null);
  assert.equal(State.promptContext, null);
  assert.equal(State.dropReader, null);
  assert.equal(State.pendingAttachment, null);

  store.files.set("saved", rec("saved", false, 1));
  State.droppedFile = dropped;
  State.pendingAttachment = dropped.path;
  assert.equal(await openConversation(store, "saved", link, chat), true);
  assert.equal(State.droppedFile, null, "opening a conversation forgets the file too");
  assert.equal(State.pendingAttachment, null);
});

test("a save still in flight when a new chat starts writes the old turns under the old id, and nothing old lands under the new id", async () => {
  fresh();
  // The store takes its write a tick later, so the save is genuinely in flight when the new chat starts.
  const store = memoryStore();
  const write = store.save;
  store.save = async (r) => {
    await new Promise((resolve) => setImmediate(resolve));
    return write(r);
  };
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "old question"), reply(2, "old answer")];
  const first = saveCurrent(store, 100);
  const oldId = State.chatId;
  startNewChat(link, chat);
  State.chatHistory.push(user(3, "new question"));
  const second = saveCurrent(store, 200);
  assert.equal(await first, true);
  assert.equal(await second, true);
  const newId = State.chatId;
  assert.notEqual(newId, oldId);
  assert.deepEqual(store.files.get(oldId).messages.map((m) => m.text), ["old question", "old answer"], "the old record holds the old turns");
  assert.deepEqual(store.files.get(newId).messages.map((m) => m.text), ["new question"], "the new record holds one message");
  assert.equal(store.files.size, 2);
  assert.ok(!JSON.stringify(store.files.get(newId)).includes("old "), "nothing old is written under the new id");
});

test("the chat's source: restored attachments never reach Bridge.aiChat, and a new chat is saved after a kept reply", () => {
  const chat = code("views/chat.ts");
  const island = code("island/island.ts");
  const session = code("companion/session.ts");

  // Only the pending file goes with a send; every ask carries pendingAttachments() or no files, and no message's attachments are read.
  assert.match(chat, /function pendingAttachments\(\): string\[\] \{\s*return State\.pendingAttachment \? \[State\.pendingAttachment\] : \[\];\s*\}/);
  assert.equal(chat.split("const attachments = pendingAttachments();").length - 1, 1);
  assert.match(chat, /Bridge\.aiChat\(req\.feature, req\.text, req\.attachments, req\.regenerate, system, req\.quick === true, onEvent\)/);
  assert.doesNotMatch(chat, /\b(?:m|msg|message|last|row|x)\.attachments\b/);
  for (const [, args] of chat.matchAll(/ask\(\{([^}]*)\}\)/g)) {
    assert.match(args, /attachments: \[\]|\battachments,|\.\.\.req/, `an ask carries no history files: ${args.trim()}`);
  }

  // A kept reply is saved (not a taken-back one), after the done event's text is set and before its sound.
  const done = chat.slice(chat.indexOf('case "done":'), chat.indexOf('case "problem":'));
  assert.match(done, /if \(State\.chatHistory\.includes\(reply\)\) autosave\(\);/);
  assert.ok(done.indexOf("reply.content = e.text") < done.indexOf("autosave("));
  assert.ok(done.indexOf("autosave(") < done.indexOf("Sound.play(\"finish\")"));

  // A drop closes the open conversation: its id goes, and the next reply is a new one.
  assert.match(island, /State\.chatEpoch\+\+;\s*State\.chatId = null;/);
  assert.match(island, /State\.chatHistory = \[\];\s*State\.localAnswers = \[\];/);

  // Nothing here keeps text, logs it, renders it as HTML or runs on a timer.
  assert.doesNotMatch(session, /console\.|localStorage|sessionStorage|innerHTML|setInterval|setTimeout|requestAnimationFrame/);
  assert.doesNotMatch(chat, /innerHTML/);
});

test("the chat's menu: the ⋯ chip is first in the row and is off during a reply; a refused pin says so", () => {
  const chat = code("views/chat.ts");
  assert.match(chat, /chipRow\.append\(menuChipEl, fileChipSlot, levelChipEl, modelChipEl\);/);
  assert.match(chat, /const menuChipEl = h\("button", \{ class: "chip settled", title: "Conversations and new chat", text: "⋯" \}\);/, "settled: the chip's border and scale are cleared");
  assert.match(chat, /menuChipEl\.toggleAttribute\("disabled", sending\);/);
  assert.match(chat, /LIST_NOTES\.pinFull/);
  assert.match(chat, /note\(OPEN_FAILED_NOTE\)/);
  assert.match(chat, /"No saved conversations yet\."/);
  assert.match(chat, /`Delete all \$\{heads\.length\} conversations\? This can't be undone\.`/);
  assert.doesNotMatch(chat, /let nextId = 1|nextId\+\+/, "the chat numbers its messages from the one counter");
});

test("Delete all from Settings: the open chat forgets its id, and its next save never writes the old rows back", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "a"), reply(2, "b")];
  await saveCurrent(store, 1);
  const openId = State.chatId;
  // Settings deleted every file; this page still holds the id and the rows on screen.
  await store.removeAll();
  assert.equal(forgetDeletedAll(link, chat), true);
  assert.equal(State.chatId, null, "the open chat forgets its id");
  assert.deepEqual(State.chatHistory, [], "the rows are not written back");
  assert.equal(chat.resets, 1);
  assert.equal(await saveCurrent(store, 2), false, "nothing is saved from the old rows");
  assert.equal(store.files.size, 0, "no file comes back under the old id");
  assert.equal(store.files.has(openId), false);
  // The second event is a no-op: nothing is reset twice.
  assert.equal(forgetDeletedAll(link, chat), false);
  assert.equal(chat.resets, 1);
});

test("Delete all from Settings: a reply after it starts a new conversation that holds only what came after", async () => {
  fresh();
  const store = memoryStore();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "old")];
  await saveCurrent(store, 1);
  const openId = State.chatId;
  await store.removeAll();
  forgetDeletedAll(link, chat);
  State.chatHistory = [user(3, "after")];
  assert.equal(await saveCurrent(store, 3), true);
  assert.notEqual(State.chatId, openId, "a new id");
  assert.deepEqual([...store.files.keys()], [State.chatId], "only the new conversation is stored");
});

test("a note in the chat is never a message of the conversation: it is not saved and not sent", () => {
  fresh();
  State.chatHistory = [user(1, "hi"), reply(2, "hello")];
  noteInChat("That conversation couldn't be opened.");
  assert.equal(State.chatHistory.at(-1).role, "note");
  assert.equal(State.chatHistory.at(-1).content, "That conversation couldn't be opened.");
  const rec = recordOf({ id: "n1", createdAt: 1, pinned: false }, State.chatHistory, 2);
  assert.deepEqual(rec.messages.map((m) => m.role), ["user", "assistant"]);
});

test("a refused autosave shows one line until a save works or the chat is new, and a late save of an old chat changes nothing", () => {
  const chat = code("views/chat.ts");
  const autosaveBody = chat.slice(chat.indexOf("function autosave() {"), chat.indexOf("function stopCountdown"));
  assert.match(autosaveBody, /const epoch = State\.chatEpoch;/);
  assert.match(autosaveBody, /void saveCurrent\(bridgeStore, Date\.now\(\)\)\.then\(\(ok\) => \{/);
  assert.match(autosaveBody, /if \(epoch !== State\.chatEpoch\) return;/);
  assert.match(autosaveBody, /unsavedAt = ok \? null : epoch;/);
  assert.match(chat, /unsavedEl\.style\.display = !out && pane === "chat" && unsavedAt !== null && unsavedAt === State\.chatEpoch \? "" : "none";/);
  assert.match(chat, /h\("div", \{ class: "chat-body" \}, poppedEl, chipRow, menu, unsavedEl, log,/);
  assert.match(chat, /const unsavedEl = h\("div", \{ class: "chat-note", style: "display: none;", text: UNSAVED_NOTE \}\);/);
});

test("the model is read again before the cloud line in a send and in both Explain flows, so the line names the brain the send uses", () => {
  const chat = code("views/chat.ts");
  const slice = (from, to) => chat.slice(chat.indexOf(from), chat.indexOf(to));
  const flows = {
    submit: slice("async function submit() {", "function continueOrRetry"),
    explainText: slice("async function explainText() {", "/** The screenshot chip"),
    explainScreenshot: slice("async function explainScreenshot() {", "/** A picture pasted"),
  };
  for (const [name, body] of Object.entries(flows)) {
    const at = body.indexOf("await refreshModel(");
    assert.ok(at > 0, `${name} reads the model again`);
    assert.ok(at < body.indexOf("cloudNoticeNow();"), `${name}: the refresh is before the notice`);
  }
});

test("the Settings window's change reaches the chat's model in both windows, the island's view and the pop-out", () => {
  const chat = code("views/chat.ts"), main = code("main.ts"), pop = code("chatwin/main.ts"), island = code("island/island.ts"), views = code("views/views.ts");
  assert.match(main, /island\.applySettings\(\);\s*island\.settingsChanged\(\);/);
  assert.match(island, /settingsChanged\(\) \{\s*void this\.views\.get\("prompt"\)\?\.refreshModel\?\.\(\);/);
  assert.match(pop, /onEvent<Settings>\("settings-changed", \(s\) => \{[\s\S]*?void chat\.refreshModel\(\);\s*\}\);/);
  assert.match(views, /refreshModel\?\(\): Promise<void>;/);
  assert.match(chat, /export function buildPrompt\(actions: ChatActions, onHeightChange: \(\) => void, link: ChatLink\): ViewHost & \{ refreshModel\(\): Promise<void> \}/);
});

test("a conversation that cannot be opened never starts quietly: the island's hand-back and the pop-out's open say so in the chat", () => {
  const main = code("main.ts"), pop = code("chatwin/main.ts");
  assert.match(main, /else if \(!\(await openConversation\(bridgeStore, State\.chatId, islandLink\(\), bridgeChat\)\)\) \{\s*startNewChat\(islandLink\(\), bridgeChat\);\s*noteInChat\(OPEN_FAILED_NOTE\);/);
  assert.match(pop, /else if \(!\(await openConversation\(bridgeStore, asked, link, bridgeChat\)\)\) \{\s*startNewChat\(link, bridgeChat\);\s*noteInChat\(OPEN_FAILED_NOTE\);/);
});

test("a pop-out that would not open keeps the island's chat: the page stops before it collapses, and the Rust command says so with a fixed sentence", () => {
  const chat = code("views/chat.ts");
  const popOut = chat.slice(chat.indexOf("async function popOut() {"), chat.indexOf("function leaveList()"));
  const refused = popOut.indexOf("if (!(await Bridge.showChatWindow(State.chatId)))");
  assert.ok(refused > 0 && popOut.indexOf("return;", refused) < popOut.indexOf("actions.collapse?.();"), "the refusal returns before the collapse");
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /if win\.show\(\)\.is_err\(\) \{\s*log::line\("chat window failed to show"\);\s*return Err\(CHAT_SHOW_FAILED\.into\(\)\);/);
  assert.match(lib, /const CHAT_SHOW_FAILED: &str = "The chat window couldn't be shown\.";/);
});

test("Delete all from Settings leaves a chat that was never saved alone", () => {
  fresh();
  const link = linkRecorder();
  const chat = recorder();
  State.chatHistory = [user(1, "draft")];
  assert.equal(forgetDeletedAll(link, chat), false);
  assert.equal(State.chatHistory.length, 1);
  assert.equal(chat.resets, 0);
});
