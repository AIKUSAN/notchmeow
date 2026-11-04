// Drift pins: the Windows and Linux Settings rules must say the same words and numbers as the Mac's Swift sources (NotchBuddy/Sources/App/Settings*.swift, read as text,
// never edited here). Each assertion names the Swift file it checks. The one allowed difference: the Sidekick's "this Mac" reads as "this computer" on Windows and Linux.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { MIN_W, MIN_H, DEFAULT_W, DEFAULT_H, BREAKPOINT, SIDEBAR_WIDE, SIDEBAR_ICONS, COLUMN_MAX, PADDING, PADDING_COLLAPSED, FIELD_MAX, NUMBER_FIELD, PICKER_WIDTH, HELP_SIZE, TAB_BAR_HEIGHT } from "../../src/settings/layout.ts";
import { PAGES, pageTitle, tabTitle, pageColor, migrate } from "../../src/settings/route.ts";
import { CAP_SENTENCE, TONE_WORDS, TONE_PREFIXES } from "../../src/settings/status.ts";
import { PERMISSION_LINE, NOTHING_LEAVES, COMES_WITH_F3A, STUCK_NAMES } from "../../src/settings/sidekicktab.ts";
import { PLAN_LINE, COMING, title, line, makeMain, getLink, serverChip, chip } from "../../src/settings/airows.ts";
import { sliceBetween } from "./slice.mjs";
import { FOLDER_ROWS, FOLDER_TITLE, POPPED_OUT_NOTE, CUT_NOTE, QUICK_TITLES, folderLabel, sentTo } from "../../src/companion/chrome.ts";
import { chatPromptHeight } from "../../src/core/layout.ts";

/** One Swift function's text: from its signature to the closing brace at its own indent (four spaces). Fails when the signature is missing. */
const swiftBody = (text, signature) => sliceBetween(text, signature, "\n    }\n");

const swift = (name) => fs.readFileSync(new URL(`../../../NotchBuddy/Sources/App/${name}`, import.meta.url), "utf8");

const ALL_TABS = ["general", "shortcuts", "yourai", "keys", "localmodels", "sidekick", "companion", "look", "outfits", "personality", "agentcats"];

test("SettingsLayout.swift: every static let number equals its layout.ts constant (SettingsLayout.swift)", () => {
  const text = swift("SettingsLayout.swift");
  const nums = new Map();
  for (const line of text.split("\n").filter((l) => l.includes("static let"))) {
    for (const m of line.matchAll(/(\w+) = ([\d.]+)/g)) nums.set(m[1], Number(m[2]));
  }
  const pairs = {
    minWidth: MIN_W, minHeight: MIN_H, defaultWidth: DEFAULT_W, defaultHeight: DEFAULT_H, breakpoint: BREAKPOINT, sidebarWide: SIDEBAR_WIDE, sidebarIcons: SIDEBAR_ICONS,
    columnMax: COLUMN_MAX, padding: PADDING, paddingCollapsed: PADDING_COLLAPSED, fieldMax: FIELD_MAX, numberField: NUMBER_FIELD, pickerWidth: PICKER_WIDTH, helpSize: HELP_SIZE, tabBarHeight: TAB_BAR_HEIGHT,
  };
  for (const [name, value] of Object.entries(pairs)) assert.equal(nums.get(name), value, `SettingsLayout.swift: ${name} must equal layout.ts`);
});


test("SettingsRoute.swift: the same pages, tabs, titles, colours and tab lists (SettingsRoute.swift)", () => {
  const text = swift("SettingsRoute.swift");
  assert.ok(text.includes("case general, agents, chat, services, cat, devices"), "SettingsRoute.swift: the page cases");
  for (const raw of ["yourai", "localmodels", "agentcats"]) assert.ok(text.includes(`"${raw}"`), `SettingsRoute.swift: raw value "${raw}"`);
  // The titles are checked inside their own functions: a comment or the other function's words cannot satisfy them.
  const pageTitles = swiftBody(text, "static func title(_ page: Page) -> String {");
  for (const p of PAGES) assert.ok(pageTitles.includes(`return "${pageTitle(p)}"`), `SettingsRoute.swift: page title "${pageTitle(p)}"`);
  const tabTitles = swiftBody(text, "static func title(_ tab: Tab) -> String {");
  for (const t of ALL_TABS) assert.ok(tabTitles.includes(`return "${tabTitle(t)}"`), `SettingsRoute.swift: tab title "${tabTitle(t)}"`);
  for (const p of PAGES) assert.ok(text.includes(`"${pageColor(p)}")`), `SettingsRoute.swift: page colour ${pageColor(p)}`);
  assert.ok(text.includes("[.yourAI, .keys, .localModels, .sidekick]"), "SettingsRoute.swift: the chat tabs");
  assert.ok(text.includes("[.look, .outfits, .personality, .agentCats]"), "SettingsRoute.swift: the cat tabs");
});

test("SettingsStatus.swift: the cap sentence and every word of tone (SettingsStatus.swift)", () => {
  const text = swift("SettingsStatus.swift");
  assert.ok(text.includes(`capSentence = "${CAP_SENTENCE}"`), `SettingsStatus.swift: capSentence = "${CAP_SENTENCE}"`);
  const start = text.indexOf("static func tone(");
  assert.ok(start >= 0, "SettingsStatus.swift: static func tone(");
  const body = text.slice(start, text.indexOf("\n    }\n", start));
  for (const w of [...TONE_WORDS.ok, ...TONE_WORDS.warn, ...TONE_WORDS.error]) {
    const inBody = w === CAP_SENTENCE ? body.includes("capSentence") : body.includes(`"${w}"`);
    assert.ok(inBody, `SettingsStatus.swift: tone() must name "${w}"`);
  }
  assert.ok(body.includes(`"${TONE_PREFIXES.ok}"`), `SettingsStatus.swift: tone() must name the prefix "${TONE_PREFIXES.ok}"`);
  assert.ok(body.includes(`"${TONE_PREFIXES.warn}"`), `SettingsStatus.swift: tone() must name the prefix "${TONE_PREFIXES.warn}"`);
});

test("SettingsSidekick.swift: the permission line, the F3a line, the four labels and nothingLeaves (SettingsSidekick.swift)", () => {
  const text = swift("SettingsSidekick.swift");
  assert.ok(text.includes(`permissionLine = "${PERMISSION_LINE}"`), `SettingsSidekick.swift: permissionLine = "${PERMISSION_LINE}"`);
  assert.ok(text.includes(`comesWithF3a = "${COMES_WITH_F3A}"`), `SettingsSidekick.swift: comesWithF3a = "${COMES_WITH_F3A}"`);
  for (const { label } of STUCK_NAMES) assert.ok(text.includes(`label: "${label}"`), `SettingsSidekick.swift: label "${label}"`);
  const swiftNothing = /nothingLeaves = "([^"]*)"/.exec(text)?.[1];
  assert.equal(swiftNothing?.replace("this Mac", "this computer"), NOTHING_LEAVES, "SettingsSidekick.swift: nothingLeaves, with this Mac read as this computer");
});

// The AI rows (airows.ts) against SettingsAI.swift.

const NO_INPUT = { claudeState: null, claudeEnabled: false, claudeModel: "sonnet", keys: [], cloudModel: {}, servers: [], memory: {} };

test("SettingsAI.swift: the plan line, the coming line and the three key titles (SettingsAI.swift)", () => {
  const text = swift("SettingsAI.swift");
  assert.ok(text.includes(`static let planLine = "${PLAN_LINE}"`), `SettingsAI.swift: planLine = "${PLAN_LINE}"`);
  assert.ok(text.includes(`static let coming = "${COMING}"`), `SettingsAI.swift: coming = "${COMING}"`);
  for (const provider of ["anthropic", "google", "openai"]) {
    const t = title({ kind: "key", provider }, NO_INPUT);
    assert.ok(text.includes(`return "${t}"`), `SettingsAI.swift: key title "${t}"`);
  }
});

test("SettingsAI.swift: the two server lines, with this Mac read as this computer (SettingsAI.swift)", () => {
  const text = swift("SettingsAI.swift");
  const server = (network) => ({ ...NO_INPUT, servers: [{ id: "s", name: "S", network, models: [] }] });
  const onNetwork = line({ kind: "server", id: "s" }, server(true));
  const onComputer = line({ kind: "server", id: "s" }, server(false));
  assert.ok(text.includes(`"${onNetwork}"`), `SettingsAI.swift: "${onNetwork}"`);
  assert.ok(text.includes(`"${onComputer.replace("this computer", "this Mac")}"`), `SettingsAI.swift: "${onComputer}" with this Mac`);
});

test("SettingsAI.swift: the five reasons Make main gives, the server chip words and the four Get URLs (SettingsAI.swift)", () => {
  const text = swift("SettingsAI.swift");
  const reasons = [
    makeMain({ kind: "claudePlan" }, NO_INPUT),
    makeMain({ kind: "openAIPlan" }, NO_INPUT),
    makeMain({ kind: "key", provider: "openai" }, NO_INPUT),
    makeMain({ kind: "key", provider: "google" }, { ...NO_INPUT, keys: ["google"] }),
    makeMain({ kind: "server", id: "s" }, { ...NO_INPUT, servers: [{ id: "s", name: "S", network: false, models: [] }] }),
  ].map((m) => m.reason);
  assert.equal(reasons.length, 5);
  for (const r of reasons) assert.ok(text.includes(`"${r}"`), `SettingsAI.swift: reason "${r}"`);
  for (const w of [serverChip("running", 0), serverChip("running", 1), serverChip("off", 0), serverChip("notInstalled", 0), serverChip("outdated", 0)]) {
    assert.ok(text.includes(`"${w}"`), `SettingsAI.swift: server chip "${w}"`);
  }
  assert.ok(text.includes('"Running, \\(models.count) models"'), "SettingsAI.swift: the running count, Running, N models");
  for (const p of ["ollama", "lmstudio", "jan", "llamacpp"]) assert.ok(text.includes(`"${getLink(p)}"`), `SettingsAI.swift: link ${getLink(p)}`);
});

test("sidekicktab.ts: STUCK_NAMES takes each label from KIND_LABELS (sidekick/settings.ts), with no second copy of the words", () => {
  const tab = fs.readFileSync(new URL("../../src/settings/sidekicktab.ts", import.meta.url), "utf8");
  const start = tab.indexOf("export const STUCK_NAMES");
  assert.ok(start >= 0, "STUCK_NAMES is declared");
  const body = tab.slice(start, tab.indexOf(";\n", start));
  assert.doesNotMatch(body, /label: "/, "STUCK_NAMES holds no label literal");
  assert.match(body, /KIND_LABELS\[kind\]/, "each label is KIND_LABELS[kind]");
  assert.match(tab, /import \{ KIND_LABELS \} from "\.\.\/sidekick\/settings\.ts";/, "KIND_LABELS is imported from the sidekick settings");
});

test("SettingsRoute.swift: migrate's four legacy tags name the same places as route.ts (SettingsRoute.swift)", () => {
  const body = swiftBody(swift("SettingsRoute.swift"), "static func migrate(storedSection: String?) -> Place {");
  // The legacy table, as the Mac writes it: each old tag and its place.
  for (const line of [
    'case "activepills": return Place(page: .general)',
    'case "integrations": return Place(page: .services)',
    'case "shortcuts": return Place(page: .general, tab: .shortcuts)',
    'case "sidekick": return Place(page: .chat, tab: .sidekick)',
  ]) assert.ok(body.includes(line), `SettingsRoute.swift migrate: ${line}`);
  // The same four on Windows and Linux (route.ts), as places. The Shortcuts tab is not shown here (no global shortcuts), so its tag falls to General, as an
  // unshown tab does everywhere; on the Mac the same tag opens General's Shortcuts tab.
  assert.deepEqual([migrate("activepills"), migrate("integrations"), migrate("shortcuts"), migrate("sidekick")], [
    { page: "general", tab: null }, { page: "services", tab: null }, { page: "general", tab: null }, { page: "chat", tab: "sidekick" },
  ]);
  // Malformed paths differ on purpose: the Mac keeps the page for `chat/keys/x` and `chat/`, while Windows and Linux send anything malformed to General (the spec's
  // "anything else goes to General"). migrate() in route.ts is the one that decides; this comment only records the difference.
  assert.deepEqual(migrate("chat/keys/x"), { page: "general", tab: null });
});

test("SettingsAI.swift: claudeChip gives the five words the Claude row's chip shows (SettingsAI.swift)", () => {
  const body = swiftBody(swift("SettingsAI.swift"), "private static func claudeChip(_ i: Input) -> String {");
  const words = [
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "signedIn", claudeEnabled: true }),
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "signedIn", claudeEnabled: false }),
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "signedOut" }),
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "notInstalled" }),
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "tooOld" }),
    chip({ kind: "claudePlan" }, { ...NO_INPUT, claudeState: "unknown" }),
  ];
  assert.deepEqual(words, ["Ready", "Off", "Not signed in", "Not installed", "Needs update", "Not ready"]);
  for (const w of words) assert.ok(body.includes(`"${w}"`), `claudeChip names "${w}"`);
});

test("SettingsSidekick.swift: the stuck switch's detail is \"N of 4\", and the example lines are the Mac's wording (SettingsSidekick.swift, SidekickStuck.swift, SidekickRecap.swift)", () => {
  const sk = swift("SettingsSidekick.swift");
  assert.ok(sk.includes('"\\(stuckKinds.count - muted) of \\(stuckKinds.count)"'), 'the detail is "N of 4" in the Mac\'s own string');
  // The example session: the same numbers as the Windows twin (sidekicktab.ts), so the picture reads the same on both.
  for (const t of ["s.project = \"my-app\"", 's.state = "approval"', "s.pendingApprovalAt = now - 30_000", "startedAt: now - 20 * SK.minute, lastEventAt: now - 5 * SK.minute"]) {
    assert.ok(sk.includes(t), `SettingsSidekick.swift example: ${t}`);
  }
  const tab = fs.readFileSync(new URL("../../src/settings/sidekicktab.ts", import.meta.url), "utf8");
  assert.ok(tab.includes('s.project = "my-app"') || tab.includes('project: "my-app"'), "sidekicktab.ts example names my-app");
  assert.ok(tab.includes("startedAt: NOW - 20 * MIN, lastEventAt: NOW - 5 * MIN"), "sidekicktab.ts example has the same clock");
  // The four lines' templates are the Mac's (SidekickStuck.swift builds them; the Windows lines come from the core's nudgeText, held equal by the contract).
  const stuck = swift("SidekickStuck.swift");
  for (const t of [
    'return "\\(agent) has run the same step \\(loopSame) times."',
    'return "\\(agent) hit \\(errors) errors in a row."',
    'return "\\(agent) is still waiting for your OK."',
    'case "stuck.silent": return "\\(agent) has been quiet for ',
  ]) assert.ok(stuck.includes(t), `SidekickStuck.swift: ${t}`);
  assert.ok(swift("SidekickRecap.swift").includes('prefix: "While you were away, "'), "the recap's opening words");
});

test("SettingsDraftBook.swift: markSaved sets what was written, isSaved is a non-empty stored value; drafts.ts keeps the same meaning with presence (SettingsDraftBook.swift, drafts.ts)", () => {
  const book = swift("SettingsDraftBook.swift");
  assert.ok(book.includes("edits[id] = stored"), "markSaved: the field shows what was really written");
  assert.ok(book.includes('func isSaved(_ id: String) -> Bool { !(saved[id] ?? "").isEmpty }'), "isSaved: a non-empty stored value");
  // The Windows book stores presence instead of text: markSaved clears the typed text, isSaved is "present" only.
  const drafts = fs.readFileSync(new URL("../../src/settings/drafts.ts", import.meta.url), "utf8");
  const mark = drafts.slice(drafts.indexOf("  markSaved(id: string, present: boolean, sent?: string): void {"), drafts.indexOf("\n  }\n", drafts.indexOf("  markSaved(id: string")));
  assert.ok(mark.includes("this.#typed.delete(id);"), "markSaved clears the typed text, as the Mac's edits[id] = stored does, when it is the text sent");
  assert.ok(drafts.includes('return this.#present.get(id) === "present";'), "isSaved is the present reading only");
  // The Mac's dirty rule is not trimmed; the Windows rule trims (spaces alone are no draft). That difference is the one the header records.
  assert.ok(book.includes('func isDirty(_ id: String) -> Bool { text(id) != (saved[id] ?? "") }'));
  assert.ok(drafts.includes("spaces alone are not a draft"), "the Windows header records the trimmed rule");
});

// The companion's words and numbers (F3a-tauri, Task 12) against the Mac's CompanionChrome.swift, CompanionQuickState.swift, ChatSizing.swift and SettingsCompanionPage.swift.
// The Windows words say "this computer" where the Mac says "this Mac"; that is the one allowed difference.

const companionSrc = () => fs.readFileSync(new URL("../../src/settings/companion.ts", import.meta.url), "utf8");
const windowsWords = (w) => w.replace("this Mac", "this computer");

test("CompanionChrome.swift: the folder rows, the folder help, the pop-out note, the cut note and the sent-to line (CompanionChrome.swift)", () => {
  const text = swift("CompanionChrome.swift");
  assert.ok(text.includes(`folderRows = [${FOLDER_ROWS.map((r) => `"${r}"`).join(", ")}]`), "folderRows");
  assert.ok(text.includes(`folderHelp = "${FOLDER_TITLE}"`), "folderHelp is FOLDER_TITLE");
  assert.ok(text.includes(`poppedOutNote = "${POPPED_OUT_NOTE}"`), "poppedOutNote");
  assert.ok(text.includes(`cutNote = "${CUT_NOTE}"`), "cutNote");
  assert.ok(text.includes('"This is sent with your messages to \\(brain)."'), "sentTo's template");
  assert.equal(sentTo("X"), "This is sent with your messages to X.", "chrome.ts sentTo is the Mac's template");
});

test("CompanionChrome.swift: folderLabel's words and the cases chrome.ts gives (CompanionChrome.swift)", () => {
  const body = swiftBody(swift("CompanionChrome.swift"), "static func folderLabel(levelKey: String, folder: String?) -> String {");
  for (const w of ['"Reads"', '"Works in"', '"No folder"']) assert.ok(body.includes(w), `folderLabel names ${w}`);
  assert.equal(folderLabel("chat", "notchmeow"), "No folder");
  assert.equal(folderLabel("read", "notchmeow"), "Reads · notchmeow");
  assert.equal(folderLabel("read", null), "Reads");
  assert.equal(folderLabel("agent", "C:\\work\\site\\"), "Works in · site");
  assert.equal(folderLabel("agent", ""), "Works in");
});

test("CompanionQuickState.swift: the two quick titles, Fixed and Rewritten (CompanionQuickState.swift)", () => {
  const text = swift("CompanionQuickState.swift");
  assert.ok(text.includes(`kind == "rewrite" ? "${QUICK_TITLES.rewrite}" : "${QUICK_TITLES.fix}"`), "the title: Rewritten for rewrite, Fixed otherwise");
});

test("ChatSizing.swift: 240 pt base, 40 pt a message, 560 at most, and layout.ts's chatPromptHeight is the same (ChatSizing.swift)", () => {
  const text = swift("ChatSizing.swift");
  const num = (name) => Number(new RegExp(`static let ${name}: CGFloat = (\\d+)`).exec(text)?.[1]);
  const base = num("baseHeight"), per = num("perMessage"), max = num("maxHeight");
  assert.deepEqual([base, per, max], [240, 40, 560], "the Swift numbers");
  assert.equal(chatPromptHeight(0), base, "an empty chat is the base");
  assert.equal(chatPromptHeight(1) - chatPromptHeight(0), per, "a message adds the per-message height");
  assert.equal(chatPromptHeight(1e6), max, "the cap");
});

test("SettingsCompanionPage.swift: the Companion tab's words are the Mac's, with this Mac read as this computer (SettingsCompanionPage.swift, companion.ts)", () => {
  const swiftText = swift("SettingsCompanionPage.swift");
  const words = [
    "Personality", "Humor", "Off", "A little", "More",
    "The cat's traits come from Cat → Personality. While an agent waits for you, it makes no jokes.",
    "What the chat knows", "See my sessions", "Project names and what your Claude Code sessions are doing, never a path or what was written.",
    "Conversations", "Delete all…", "Kept on this Mac, 50 at most; the oldest unpinned goes first.",
    "What the AI saw last", "Show", "Done", "Delete all", "Nothing sent since NotchMeow started.", "Kept in memory only, gone when NotchMeow quits.",
    "Delete all saved conversations?", "Every saved conversation on this Mac is deleted. This cannot be undone.",
  ];
  const tab = companionSrc() + fs.readFileSync(new URL("../../src/settings/companionrules.ts", import.meta.url), "utf8");
  for (const w of words) {
    assert.ok(swiftText.includes(`"${w}"`), `SettingsCompanionPage.swift: "${w}"`);
    assert.ok(tab.includes(windowsWords(w)), `companion.ts: "${windowsWords(w)}"`);
  }
  assert.ok(swiftText.includes('model.conversations) saved"'), "SettingsCompanionPage.swift: the count line reads N saved");
  assert.ok(tab.includes("saved`"), "companion.ts: the count line reads N saved");
});
