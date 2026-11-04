// A failed settings save is visible and reverts (Task 2 of the Windows and Linux Settings polish). The decisions are pure (src/settings/savestate.ts): the save flow runs here
// through `makeSaver` against a fake store that rejects, with two saves overlapping. The pins read the page's source, because Node has no DOM: the focus read, the forced
// revert, the strip, the card note and the bridge's checked call are held by text.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { saveOutcome, notePlacement, storedAfterEcho, tidyEcho, makeSaver } from "../../src/settings/savestate.ts";
import { cleanCatBlock } from "../../src/cat/display.ts";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const SETTINGS = "src/settings/";
const app = read(`${SETTINGS}app.ts`);
const kit = read(`${SETTINGS}kit.ts`);
const shell = read(`${SETTINGS}shell.ts`);
const ctx = read(`${SETTINGS}ctx.ts`);
const backend = read(`${SETTINGS}backend.ts`);
const devseed = read(`${SETTINGS}devseed.ts`);
const main = read(`${SETTINGS}main.ts`);
const savestate = read(`${SETTINGS}savestate.ts`);
const bridge = read("src/core/bridge.ts");
const css = read(`${SETTINGS}settings.css`);

/** One top-level function's text: from `export function NAME(` to the closing brace at column 0. */
function fnText(text, name) {
  const start = text.indexOf(`export function ${name}(`);
  assert.ok(start >= 0, `export function ${name} exists`);
  const end = text.indexOf("\n}\n", start);
  assert.ok(end > start, `${name} closes at column 0`);
  return text.slice(start, end + 3);
}

const STORED = { soundEnabled: true, screen: "primary" };
const NEXT = { soundEnabled: false, screen: "primary" };
const OLDER = { soundEnabled: true, screen: "cursor" };

// ── The pure decision ──

test("a save the store confirms becomes the stored value and reverts nothing", () => {
  assert.deepEqual(saveOutcome(STORED, NEXT, true, 1, 1), { stored: NEXT, revert: false });
});

test("a refused save of the latest change keeps the stored value and reverts", () => {
  assert.deepEqual(saveOutcome(STORED, NEXT, false, 1, 1), { stored: STORED, revert: true });
});

test("a refused save that a newer save has overtaken does not revert", () => {
  assert.deepEqual(saveOutcome(STORED, NEXT, false, 1, 2), { stored: STORED, revert: false });
});

test("a confirmed save that a newer save has overtaken is still what the store holds", () => {
  assert.deepEqual(saveOutcome(STORED, OLDER, true, 1, 2), { stored: OLDER, revert: false });
});

test("the note goes in the card of the control in use, and on the strip when no card holds it", () => {
  // A stand-in for an element: notePlacement only asks whether there is a card.
  const cardStandIn = { nodeType: 1, tagName: "SECTION", className: "st-card" };
  assert.equal(notePlacement(cardStandIn), "card", "a card takes the note");
  assert.equal(notePlacement(null), "strip");
});

test("an echo is cleaned the way boot cleans: a cat block it carries is cleaned, and an echo without one stays without one", () => {
  const dirty = { coat: "not-a-coat", size: 999 };
  assert.deepEqual(tidyEcho({ soundEnabled: false }), { soundEnabled: false }, "a partial echo stays partial");
  assert.deepEqual(tidyEcho({ cat: dirty }).cat, cleanCatBlock(dirty), "a carried cat block is cleaned");
  assert.notDeepEqual(tidyEcho({ cat: dirty }).cat, dirty);
});

test("an echo from the store becomes the stored value: a partial echo keeps the rest, and an older one never rewinds a newer one", () => {
  assert.deepEqual(storedAfterEcho(STORED, { soundEnabled: false }), { soundEnabled: false, screen: "primary" });
  // Echoes arrive in the order Rust made them (save_settings is synchronous), so the last one is the state held.
  const afterFirst = storedAfterEcho(STORED, NEXT);
  const afterSecond = storedAfterEcho(afterFirst, OLDER);
  assert.deepEqual(afterSecond, OLDER);
});

// ── The flow, with a rejecting fake store ──

/** A promise the test settles by hand, so two saves can overlap in the order the test chooses. */
function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
}

/** The window's ports as a fake: every call is recorded, the store answers from the deferreds in the order they are given. */
function fakePorts(answers) {
  const log = { shown: [], reverts: [], notes: [], clears: 0 };
  const focusEl = { id: "control" };
  const card = { id: "card" };
  const ports = {
    write: () => answers.shift().promise,
    show: (s) => log.shown.push(s),
    focus: () => ({ el: focusEl, card }),
    page: () => "general",
    revert: (only) => log.reverts.push(only),
    note: (place, c) => log.notes.push({ place, card: c }),
    clear: () => { log.clears += 1; },
  };
  return { ports, log, focusEl, card };
}

test("two saves overlap: the earlier is refused after the later was confirmed, and nothing reverts", async () => {
  const first = deferred();
  const second = deferred();
  const { ports, log } = fakePorts([first, second]);
  const saver = makeSaver(ports, STORED);
  const p1 = saver.save(NEXT);
  const p2 = saver.save(OLDER);
  second.resolve(true);
  assert.equal(await p2, true, "the later save is confirmed");
  first.resolve(false);
  assert.equal(await p1, false, "the earlier save is refused");
  assert.deepEqual(saver.stored(), OLDER, "the stored value is the one the store confirmed last");
  assert.deepEqual(log.reverts, [], "an overtaken refusal reverts nothing");
  assert.deepEqual(log.notes, [], "and says nothing");
});

test("two saves overlap: the earlier is confirmed, then the later is refused, and the window goes back to the earlier", async () => {
  const first = deferred();
  const second = deferred();
  const { ports, log, focusEl, card } = fakePorts([first, second]);
  const saver = makeSaver(ports, STORED);
  const p1 = saver.save(NEXT);
  const p2 = saver.save(OLDER);
  first.resolve(true);
  assert.equal(await p1, true);
  assert.deepEqual(saver.stored(), NEXT, "the earlier confirmed value is stored");
  second.resolve(false);
  assert.equal(await p2, false);
  assert.deepEqual(saver.stored(), NEXT, "a refused save never becomes the stored value");
  assert.deepEqual(log.shown.at(-1), NEXT, "the window goes back to the stored value");
  assert.deepEqual(log.reverts, [focusEl], "the refused control is redrawn, even while in use");
  assert.deepEqual(log.notes, [{ place: "card", card }], "the note goes into the card the control is in");
});

test("a refusal with nothing in focus puts the note on the strip, with no card", async () => {
  const only = deferred();
  const { ports, log } = fakePorts([only]);
  ports.focus = () => null;
  const saver = makeSaver(ports, STORED);
  const p = saver.save(NEXT);
  only.resolve(false);
  await p;
  assert.deepEqual(log.notes, [{ place: "strip", card: null }]);
  assert.deepEqual(log.reverts, [null]);
});

test("a refusal after the page changed reverts the controls but puts no note on the new page", async () => {
  const only = deferred();
  const { ports, log } = fakePorts([only]);
  let page = "general";
  ports.page = () => page;
  const saver = makeSaver(ports, STORED);
  const p = saver.save(NEXT);
  page = "services";
  only.resolve(false);
  await p;
  assert.equal(log.reverts.length, 1, "the controls go back");
  assert.deepEqual(log.notes, [], "the note is not put on the other page");
});

test("a confirmed save clears the note, and a refused one clears the old note before it shows the new one", async () => {
  const a = deferred();
  const b = deferred();
  const { ports, log } = fakePorts([a, b]);
  const saver = makeSaver(ports, STORED);
  const p1 = saver.save(NEXT);
  a.resolve(true);
  await p1;
  assert.equal(log.clears, 1, "a confirmed save clears");
  const p2 = saver.save(OLDER);
  b.resolve(false);
  await p2;
  assert.equal(log.clears, 2, "a refusal clears the old note before the new one");
  assert.equal(log.notes.length, 1);
});

test("a store that rejects the write is a refusal: the window goes back, the note is shown, and the save resolves false", async () => {
  const { ports, log, focusEl, card } = fakePorts([]);
  ports.write = () => Promise.reject(new Error("the credential store is locked"));
  const saver = makeSaver(ports, STORED);
  assert.equal(await saver.save(NEXT), false, "the save resolves, as a refusal");
  assert.deepEqual(saver.stored(), STORED, "the stored value stays what the store confirmed");
  assert.deepEqual(log.shown.at(-1), STORED, "the window goes back to it");
  assert.deepEqual(log.reverts, [focusEl]);
  assert.deepEqual(log.notes, [{ place: "card", card }]);
});

// ── Source pins ──

test("the strip and the note are placed by the pure rule, and the focus is read before the first await", () => {
  const body = savestate.slice(savestate.indexOf("export function makeSaver"));
  assert.ok(body.indexOf("ports.focus()") > 0 && body.indexOf("ports.focus()") < body.indexOf("await ports.write"), "focus is read before the store is asked");
  assert.match(body, /notePlacement\(at\?\.card \?\? null\)/, "the placement is the pure one, given the card");
  assert.match(body, /ports\.page\(\) === page/, "a note only goes to the page the save was made on");
});

test("app.ts wires makeSaver to the DOM: the focused control and its card, the forced revert, the card note and the strip", () => {
  assert.match(app, /makeSaver\(\{/, "app.ts builds the saver");
  assert.match(app, /document\.activeElement/, "the focused control is read");
  assert.match(app, /closest<HTMLElement>\("\.st-card"\)/, "the card that holds the control is found");
  assert.match(app, /forceValues\(\(\) => shell\?\.sync\(\), only\)/, "the revert forces only the refused control");
  assert.match(app, /cardNote\(card, "Couldn't save\."\)/, "the note goes into the card");
  assert.match(app, /banner\(\{ text: "Couldn't save\." \}\)/, "the strip says it when there is no card");
  assert.match(app, /page: \(\) => shell\?\.current\(\)\.page \?\? ""/, "the saver compares pages by name, read from the shell");
  assert.match(app, /saver\.echo\(tidyEcho\(s\)\)/, "the echo feeds the stored value, cleaned as boot cleans");
  assert.match(app, /function clearNote\(\)/, "one clearNote closure");
});

test("ctx.save resolves with a boolean and the backend's save reports whether the store confirmed it", () => {
  assert.match(ctx, /save\(next: Settings\): Promise<boolean>;/);
  assert.match(backend, /save\(settings: Settings\): Promise<boolean>;/);
  assert.match(backend, /save: \(settings\) => Bridge\.saveSettingsChecked\(settings\)/, "the bridge backend uses the checked save");
});

test("the island's own save keeps its fire-and-forget call, and call() is built over callChecked", () => {
  assert.match(bridge, /saveSettings: \(settings: Settings\) => call<void>\("save_settings", \{ settings \}\),/);
  assert.match(bridge, /saveSettingsChecked: async \(settings: Settings\): Promise<boolean>/);
  assert.match(bridge, /async function callChecked<T>\(cmd: string, args\?: Record<string, unknown>\): Promise<Checked<T>>/, "callChecked is the checked variant of call");
  assert.match(bridge, /export type Checked<T> = \{ ok: true; value: T \| null \} \| \{ ok: false; error: string \};/, "its answer type");
  assert.match(bridge, /value: \(await invoke<T>\(cmd, args\)\) \?\? null/, "a missing value is null");
  const callFn = bridge.slice(bridge.indexOf("async function call<T>"), bridge.indexOf("\n}\n", bridge.indexOf("async function call<T>")));
  assert.match(callFn, /callChecked<T>\(cmd, args\)/, "call() goes through callChecked");
});

test("kit.ts: forceValues lets the forced sync write only the refused control, and every other field keeps what is typed", () => {
  assert.match(fnText(kit, "forceValues"), /forcedFor = only/);
  assert.match(fnText(kit, "setValue"), /el === forcedFor \|\| el !== document\.activeElement/, "setValue's guard is skipped only for the refused control");
});

test("kit.ts: cardNote and clearCardNote make one st-cardnote notice at the top of a card", () => {
  assert.match(fnText(kit, "cardNote"), /notice\("err", text\)/);
  assert.match(fnText(kit, "cardNote"), /st-cardnote/);
  assert.match(fnText(kit, "cardNote"), /note\.setAttribute\("role", "alert"\)/, "the card note is an alert, set before it is inserted");
  assert.match(fnText(kit, "clearCardNote"), /st-cardnote/);
  assert.doesNotMatch(kit, /#[0-9a-fA-F]{3,8}\b|rgba?\(/, "no colour literals in the kit");
});

test("the shell's strip is a hidden element above the column, cleared on a page change", () => {
  assert.match(shell, /const strip = h\("div", \{ class: "st-strip", hidden: true, role: "alert" \}\)/, "an alert: a note put in after a failure is read out");
  assert.match(shell, /const pinned = h\("div", \{ class: "st-strip", hidden: true, role: "alert" \}\)/, "the boot banner is announced too");
  const i = shell.indexOf("function select(place: Place)");
  assert.match(shell.slice(i, shell.indexOf("// One listener", i)), /banner\(null\)/, "a page change clears the strip");
});

test("settings.css has the two rules for the strip and the card note, with tokens only", () => {
  const start = css.indexOf(".st-strip");
  assert.ok(start > 0, "the strip has a rule");
  const rules = css.slice(start, css.indexOf("/* Wardrobe (sub-project I)"));
  assert.match(rules, /\.st-strip\[hidden\] \{ display: none; \}/, "a hidden strip takes no room");
  assert.match(rules, /\.st-cardnote \{/, "the card note has a rule");
  assert.doesNotMatch(rules, /#[0-9a-fA-F]{3,8}\b|rgba?\(/, "no colour literals");
});

test("the new code has no timer, poll or observer", () => {
  for (const [name, text] of [["app.ts", app], ["kit.ts", kit], ["shell.ts", shell], ["savestate.ts", savestate]]) {
    assert.doesNotMatch(text, /setTimeout|setInterval|MutationObserver|ResizeObserver|IntersectionObserver/, name);
  }
});

test("the dev backend refuses one save under ?failsave, and the dev route takes 1 (focused) or strip (no control in focus)", () => {
  assert.match(devseed, /failSave && state === "error"/);
  assert.match(main, /get\("failsave"\)/);
  assert.match(main, /failsave.*strip|"strip"/, "the strip picture is a dev value");
  assert.match(main, /import\.meta\.env\.DEV/);
});
