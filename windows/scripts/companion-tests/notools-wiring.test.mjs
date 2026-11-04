import test from "node:test";
import assert from "node:assert/strict";
import { code } from "../projects-tests/util.mjs";

// The no-tools level on the page (Task 8, docs/superpowers/plans/2026-10-28-claude-no-tools-level.md): an Explain turn is quick, the chat is held at
// `none` from the Explain's start, the Folder control shows "No tools" through folderLabel, and the picker never offers or sends `none`. Rust keeps the
// real hold (quick_hold); the page only mirrors it in State.claudeLevel. Comments are blanked first.

const chat = code("views/chat.ts"), bridge = code("core/bridge.ts"), state = code("core/state.ts"), session = code("companion/session.ts"), claude = code("core/claude.ts");

/** The text of one function: from its header to the given closing text (the first one after the header). */
function body(src, header, end = "\n  }\n") {
  const start = src.indexOf(header);
  assert.ok(start >= 0, `${header} is found`);
  return src.slice(start, src.indexOf(end, start));
}

test("the page's level type has the none level, and the chip words come from levelChip and folderLabel", () => {
  assert.match(claude, /export type ClaudeLevel = "chat" \| "read" \| "agent" \| "none";/);
  assert.match(body(claude, "export function levelChip(", "\n}\n"), /none: "No tools"/);
  assert.match(body(claude, "export function levelChip(", "\n}\n"), /level === "chat" \|\| level === "none" \|\| !folder/);
});

test("an Explain turn is a quick turn: explainText asks with quick: true, as explainScreenshot does", () => {
  assert.match(body(chat, "  async function explainText() {"), /void ask\(\{ text: r\.user, attachments: \[\], feature: "chat", regenerate: false, retries: 0, system: r\.system, quick: true \}\);/);
  assert.match(body(chat, "  async function explainScreenshot() {"), /void ask\(\{ text: r\.user, attachments, feature: "files", regenerate: false, retries: 0, system: r\.system, quick: true \}\);/);
});

test("both explain functions hold the chat at none right after startNewChat, before their turn is asked", () => {
  for (const header of ["  async function explainText() {", "  async function explainScreenshot() {"]) {
    const fn = body(chat, header);
    assert.match(fn, /startNewChat\(link, bridgeChat\);\s*State\.claudeLevel = \{ level: "none", folder: null \};/, `${header} sets the hold right after startNewChat`);
    assert.ok(fn.indexOf('level: "none"') < fn.indexOf("void ask("), `${header} sets the hold before the ask`);
  }
  assert.equal(chat.split('State.claudeLevel = { level: "none", folder: null };').length - 1, 2, "only the two explain functions set the hold");
});

test("Fix and Rewrite never touch the level: their own session is always none and the chat's level stays as it is", () => {
  assert.doesNotMatch(body(chat, "  async function quickFix("), /claudeLevel/);
});

test("ask passes the turn's quick flag to Bridge.aiChat as its sixth argument, and the bridge sends it to ai_chat as quick", () => {
  assert.match(chat, /Bridge\.aiChat\(req\.feature, req\.text, req\.attachments, req\.regenerate, system, req\.quick === true, onEvent\)/);
  assert.match(bridge, /aiChat: \([\s\S]*?system: string,\s*quick: boolean,\s*onEvent: \(event: AiEvent\) => void,?\s*\)/);
  assert.match(bridge, /callOrThrow<void>\("ai_chat", \{ feature, text, attachments, regenerate, system, quick, onEvent: channel \}\)/);
});

test("the picker never sends none: claudeSetLevel is called once, inside chooseLevel, and no row or pick is none", () => {
  assert.equal(chat.split("Bridge.claudeSetLevel(").length - 1, 1, "claudeSetLevel is called once");
  assert.match(body(chat, "  async function chooseLevel(", "\n  }\n"), /Bridge\.claudeSetLevel\(level, folder\)/);
  assert.doesNotMatch(chat, /chooseLevel\("none"/);
  assert.doesNotMatch(chat, /row\(FOLDER_ROWS\[\d\], [^\n]*"none"/);
  assert.match(chat, /class: State\.claudeLevel\.level === level \? "picker-item on" : "picker-item"/, "a row is current only when its own level is the chat's");
});

test("the Folder control reads folderLabel of the chat's level, so the hold shows No tools", () => {
  assert.match(chat, /levelChipEl\.textContent = folderLabel\(State\.claudeLevel\.level, State\.claudeLevel\.folder\);/);
});

test("a new chat and an opened conversation reset the level to Chat only: startNewChat calls resetClaude, and resetClaude sets chat", () => {
  assert.match(body(session, "export function startNewChat(", "\n}\n"), /State\.resetClaude\(\);/);
  assert.match(body(state, "  resetClaude() {"), /this\.claudeLevel = \{ level: "chat", folder: null \};/);
});
