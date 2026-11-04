import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { code, source } from "../projects-tests/util.mjs";

// The Companion's dev samples (Task 11) and the Conversations pane's layout. The samples are dev-only routes that drive the chat with stand-ins; inside the app's own
// webview they must never run (they would reach the real Bridge and overwrite the live State). The pane must fill the chat's free height with its footer in view.
// Pinned by source reads (comments blanked first), as the other Companion checks are.

const dev = code("companion/devcompanion.ts");
const chatwin = code("chatwin/main.ts");
const chat = code("views/chat.ts");
const css = source("companion/companion.css");
const styleCss = source("style.css");

/** The text of one top-level function of a file, from its header to the closing brace at column 0. */
function fnText(text, header) {
  const at = text.indexOf(header);
  assert.ok(at >= 0, `${header} exists`);
  const end = text.indexOf("\n}\n", at);
  assert.ok(end > at, `${header} closes`);
  return text.slice(at, end + 2);
}

test("the sample chat never runs inside the app's webview: mountChatSample and mountCompanionDev check IS_TAURI before any chat or State change", () => {
  assert.match(dev, /import \{[^}]*\bIS_TAURI\b[^}]*\} from "\.\.\/core\/bridge\.ts";/);
  const sample = fnText(dev, "export function mountChatSample(");
  assert.ok(sample.indexOf("if (IS_TAURI)") >= 0, "the guard is in mountChatSample");
  assert.ok(sample.indexOf("if (IS_TAURI)") < sample.indexOf("applyScene(scene)"), "the guard comes before applyScene");
  assert.ok(sample.indexOf("if (IS_TAURI)") < sample.indexOf("buildChat("), "the guard comes before the chat is built");
  const panel = fnText(dev, "export function mountCompanionDev(");
  assert.ok(panel.indexOf("if (IS_TAURI)") < panel.indexOf("buildChat("), "the guard comes before the chat is built");
  assert.ok(panel.indexOf("mountPromptOnly(root, before)") > panel.indexOf("if (IS_TAURI)"), "the app window mounts the Prompt box only");
});

test("the app window's Prompt box calls no Bridge, builds no chat and writes no State", () => {
  const only = fnText(dev, "function mountPromptOnly(");
  assert.doesNotMatch(only, /Bridge\./);
  assert.doesNotMatch(only, /buildChat|applyScene|State\.(chatHistory|localAnswers|quickResult|droppedFile|pendingAttachment|claudeLevel)\s*=/);
  assert.ok(only.includes("IN_APP_NOTE"), "the Prompt box carries the line");
});

test("the app window's line says the samples run in a browser", () => {
  assert.match(dev, /export const IN_APP_NOTE = "The chat samples run in a browser, not in the app window\.";/);
  const note = fnText(dev, "function inAppNote(");
  assert.ok(note.includes("IN_APP_NOTE"));
});

test("the chat window's sample route is dev-only, and it hands its work to the samples module only then", () => {
  assert.match(chatwin, /if \(import\.meta\.env\.DEV && sample\.get\("sample"\) === "1"\) \{/);
  assert.match(chatwin, /import\("\.\.\/companion\/devcompanion\.ts"\)\.then\(\(m\) => m\.mountChatSample\(root, sample\.get\("scene"\) \?\? ""\)\)/);
});

test("the Conversations pane fills the chat's free height: its rows scroll in their own box and the footer is a fixed row at the bottom", () => {
  assert.match(chat, /const listPane = h\("div", \{ class: "model-picker cm-pane" \}\);/);
  const list = fnText(chat, "  function drawList() {");
  assert.ok(list.includes('h("div", { class: "cm-pane-rows" })'), "the rows have their own box");
  assert.ok(list.includes('h("div", { class: "cm-pane-foot" })'), "the footer has its own box");
  assert.ok(list.indexOf('foot.append(h("button", { class: "note-btn", text: PANE.deleteAll') > 0, "Delete all is in the footer");
  assert.ok(list.indexOf("listPane.append(rows, foot);") > 0, "the rows and the footer go in the pane last");
});

test("companion.css overrides the pane only on its own classes, and style.css keeps the shipped picker at 120 px", () => {
  assert.match(css, /\.chat-body > \.cm-pane \{[^}]*flex: 1 1 auto;[^}]*max-height: none;/s);
  assert.match(css, /\.chat-body > \.cm-pane > \.cm-pane-rows \{[^}]*overflow-y: auto;/s);
  assert.match(css, /\.chat-body > \.cm-pane > \.cm-pane-foot \{[^}]*flex: 0 0 auto;/s);
  assert.match(styleCss, /\.model-picker \{[^}]*max-height: 120px;/s, "the shipped .model-picker rule is unchanged");
});

test("the pictures script draws the Conversations pane at the short chat height too, and its Chrome run takes no stdin", () => {
  const script = fs.readFileSync(new URL("../../scripts/render-companion.sh", import.meta.url), "utf8");
  assert.match(script, /conversations-small\|conversations\|640\|300/);
  assert.match(script, /--virtual-time-budget=5000 "\$@" 2>>"\$CHROME_LOG" <\/dev\/null/);
});
