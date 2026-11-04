import test from "node:test";
import assert from "node:assert/strict";
import { BRING_BACK, CUT_NOTE, FOLDER_ROWS, FOLDER_TITLE, LIST_NOTES, MENU, OPEN_FAILED_NOTE, PANE, POPPED_OUT_NOTE, QUICK_TITLES, SCREENSHOT_CHIP, UNSAVED_NOTE, folderLabel, sentTo } from "../../src/companion/chrome.ts";
import { code } from "../projects-tests/util.mjs";

// The companion's words (Mac: CompanionChrome.swift; Task 12 pins them to the Mac's). They are strings the chat shows, never rules.

test("the level chip reads No folder, Reads · <folder> or Works in · <folder>, and the bare word without a folder", () => {
  assert.equal(folderLabel("chat", null), "No folder");
  assert.equal(folderLabel("chat", "C:\\dev\\notchmeow"), "No folder");
  assert.equal(folderLabel("read", "C:\\dev\\notchmeow"), "Reads · notchmeow");
  assert.equal(folderLabel("agent", "/home/dev/site/"), "Works in · site");
  assert.equal(folderLabel("agent", null), "Works in");
  assert.equal(folderLabel("read", null), "Reads");
  assert.equal(folderLabel("none", null), "No tools");
});

test("the rows, the chip's title and the other companion words are the Mac's", () => {
  assert.deepEqual(FOLDER_ROWS, ["No folder", "Read a folder…", "Work in a folder…"]);
  assert.equal(FOLDER_TITLE, "The folder Claude may use in this chat");
  assert.equal(POPPED_OUT_NOTE, "The chat is in its own window.");
  assert.equal(BRING_BACK, "Bring it back");
  assert.deepEqual(QUICK_TITLES, { fix: "Fixed", rewrite: "Rewritten" });
  assert.equal(CUT_NOTE, "Cut to the first 8,000 characters.");
  assert.equal(SCREENSHOT_CHIP, "Explain this screenshot");
  assert.deepEqual(MENU, { newChat: "New chat", conversations: "Conversations", popOut: "Pop out", fix: "Fix", rewrite: "Rewrite", explain: "Explain" });
});

test("the pane words keep their wording, and the sent-to line names the brain", () => {
  assert.equal(PANE.deleteAll, "Delete all");
  assert.equal(PANE.unpin, "Unpin");
  assert.equal(sentTo("Claude · your plan"), "This is sent with your messages to Claude · your plan.");
});

test("chat.ts shows the level chip, the rows and the menu from chrome.ts, and no longer from the old strings", () => {
  const chat = code("views/chat.ts");
  assert.doesNotMatch(chat, /levelChip\(/, "the old chip words are no longer called");
  assert.equal(chat.split("folderLabel(").length - 1, 1, "the chip's words are asked once");
  assert.match(chat, /title: FOLDER_TITLE/);
  assert.match(chat, /row\(FOLDER_ROWS\[0\], /);
  assert.match(chat, /row\(FOLDER_ROWS\[1\], /);
  assert.match(chat, /row\(FOLDER_ROWS\[2\], /);
  assert.match(chat, /text: MENU\.newChat/);
  assert.match(chat, /text: MENU\.conversations/);
  assert.doesNotMatch(chat, /row\("(Chat only|Read-only|Agent)"|text: "(New chat|Conversations)"|title: "What Claude may do in this chat"/);
});

test("the words of the silent failures are the ones the chat and the pane show, and the Mac has none of them", () => {
  assert.equal(UNSAVED_NOTE, "This chat isn't saved.");
  assert.equal(OPEN_FAILED_NOTE, "That conversation couldn't be opened.");
  assert.deepEqual({ ...LIST_NOTES }, {
    deleteOne: "Couldn't delete that one.",
    deleteAll: "Couldn't delete the conversations.",
    pin: "Couldn't pin it.",
    rename: "Couldn't rename it.",
    pinFull: "Unpin one to pin another.",
  });
  const chat = code("views/chat.ts");
  assert.match(chat, /h\("div", \{ class: "chat-note", style: "display: none;", text: UNSAVED_NOTE \}\)/);
  assert.match(chat, /note\(OPEN_FAILED_NOTE\)/);
  assert.match(chat, /listNote = ok \? "" : LIST_NOTES\.deleteOne;/);
  assert.match(chat, /listNote = ok \? "" : LIST_NOTES\.deleteAll;/);
  assert.match(chat, /listNote = r === "full" \? LIST_NOTES\.pinFull : r === "failed" \? LIST_NOTES\.pin : "";/);
  assert.match(chat, /if \(t && !\(await rename\(bridgeStore, c\.id, t, Date\.now\(\)\)\)\) listNote = LIST_NOTES\.rename;/);
  assert.doesNotMatch(chat, /couldn't be opened\.|Unpin one to pin another\./, "the words live in chrome.ts only");
});

test("main.ts loads the companion's stylesheet beside the other CSS imports", () => {
  assert.match(code("main.ts"), /import "\.\/companion\/companion\.css";/);
});
