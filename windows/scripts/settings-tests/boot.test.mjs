// A failed settings read is visible and never writes defaults (Task 3 of the Windows and Linux Settings polish, fix round 1). The rule is pure (src/settings/bootstate.ts):
// what the boot shows, which buttons each case offers, and the words. The wiring is pinned as text, because Node has no DOM: the boot branch and the answer handlers in
// app.ts, the pinned strip in shell.ts (a page change does not clear it), the Bridge and backend calls, the dev route's ?bootproblem=, and the commands registered in Rust.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { bootState, bannerText, fileName } from "../../src/settings/bootstate.ts";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { sliceBetween } from "./slice.mjs";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const SETTINGS = "src/settings/";
const app = read(`${SETTINGS}app.ts`);
const shell = read(`${SETTINGS}shell.ts`);
const backend = read(`${SETTINGS}backend.ts`);
const main = read(`${SETTINGS}main.ts`);
const devseed = read(`${SETTINGS}devseed.ts`);
const bridge = read("src/core/bridge.ts");
const lib = read("src-tauri/src/lib.rs");
const settingsRs = read("src-tauri/src/settings.rs");
const aiRs = read("src-tauri/src/ai/mod.rs");
/** A Rust function by name: from its signature to the closing brace at column 0. */
const rustFn = (text, name) => sliceBetween(text, new RegExp(`(?:pub )?(?:async )?fn ${name}\\(`), "\n}\n");

/** A boot payload as Rust sends it, with the fields the rule does not read filled in. */
function bootInfo(extra = {}) {
  return {
    settings: { ...DEFAULT_SETTINGS, screen: "cursor" },
    screen: { x: 0, y: 0, width: 1920, height: 1080, scale: 1 },
    version: "1.0.0", hookPath: "", cursorPoll: true, desktopPositioned: true,
    home: "", shelf: { dragOut: true, send: true }, claudeApp: false,
    ...extra,
  };
}

/** One function's text inside app.ts or shell.ts: from `function NAME(` to the closing brace at two spaces. */
function innerFn(text, name) {
  const start = text.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `function ${name} exists`);
  const end = text.indexOf("\n  }\n", start);
  assert.ok(end > start, `${name} closes`);
  return text.slice(start, end + 5);
}

// ── The rule ──

test("inside Tauri, a boot the command failed on is a failed boot: the defaults, and only Try again", () => {
  const s = bootState(undefined, true);
  assert.deepEqual(s.banner, { kind: "failed" });
  assert.deepEqual(s.buttons, ["Try again"], "Start fresh is not offered while Rust has not seen the file unreadable");
  assert.deepEqual(s.settings, DEFAULT_SETTINGS);
});

test("outside Tauri, a boot that is undefined is no problem: no banner, no buttons, the defaults (the plain-browser page works as before)", () => {
  const s = bootState(undefined, false);
  assert.equal(s.banner, null);
  assert.deepEqual(s.buttons, []);
  assert.deepEqual(s.settings, DEFAULT_SETTINGS);
});

test("a boot with no problem has no banner and keeps the settings it sent", () => {
  const s = bootState(bootInfo(), true);
  assert.equal(s.banner, null);
  assert.deepEqual(s.buttons, []);
  assert.equal(s.settings.screen, "cursor");
});

test("a boot with a null problem (the key Rust always sends) has no banner", () => {
  assert.equal(bootState(bootInfo({ settingsProblem: null }), true).banner, null);
});

test("an unreadable file offers Try again and Start fresh, with no file name", () => {
  const s = bootState(bootInfo({ settingsProblem: { kind: "unreadable" } }), true);
  assert.deepEqual(s.banner, { kind: "unreadable" });
  assert.deepEqual(s.buttons, ["Try again", "Start fresh"]);
  assert.equal(s.settings.screen, "cursor", "the defaults Rust sent are what is shown");
});

test("an unparseable file names the kept copy and offers Dismiss only (a retry would only read the same broken file)", () => {
  const s = bootState(bootInfo({ settingsProblem: { kind: "unparseable", keptAs: "settings.json.bad-20261020-101010" } }), true);
  assert.deepEqual(s.banner, { kind: "unparseable", keptAs: "settings.json.bad-20261020-101010" });
  assert.deepEqual(s.buttons, ["Dismiss"]);
});

test("a path that reaches the page is cut to its file name: the page never shows a folder", () => {
  const s = bootState(bootInfo({ settingsProblem: { kind: "unparseable", keptAs: "C:\\Users\\sample\\AppData\\Roaming\\NotchMeow\\settings.json.bad-1" } }), true);
  assert.equal(s.banner.keptAs, "settings.json.bad-1");
  assert.equal(fileName("/home/sample/.config/notchmeow/settings.json.bad-2"), "settings.json.bad-2");
});

test("an unparseable file with no name still gets a banner that says a copy was kept", () => {
  const s = bootState(bootInfo({ settingsProblem: { kind: "unparseable" } }), true);
  assert.deepEqual(s.banner, { kind: "unparseable" });
  assert.deepEqual(s.buttons, ["Dismiss"]);
});

// ── The words ──

test("the unreadable words: defaults are shown, nothing is saved until the person chooses, and Start fresh replaces the file with the next change", () => {
  assert.equal(
    bannerText({ kind: "unreadable" }),
    "Your settings couldn't be read, so you are seeing defaults. Nothing is saved until you choose. Start fresh replaces it with your next change.",
  );
});

test("the failed-boot words: nothing is saved until Try again works, and no Start fresh is named", () => {
  assert.equal(
    bannerText({ kind: "failed" }),
    "Your settings couldn't be loaded, so you are seeing defaults. Nothing is saved until Try again works.",
  );
});

test("the unparseable words name the kept copy, and only its name", () => {
  assert.equal(
    bannerText({ kind: "unparseable", keptAs: "settings.json.bad-1" }),
    "Your settings file couldn't be read. It was kept as settings.json.bad-1; you are seeing defaults.",
  );
});

test("the unparseable words without a name say a copy was kept", () => {
  assert.equal(bannerText({ kind: "unparseable" }), "Your settings file couldn't be read. A copy was kept; you are seeing defaults.");
});

test("no banner word carries a path separator", () => {
  for (const b of [{ kind: "failed" }, { kind: "unreadable" }, { kind: "unparseable", keptAs: "settings.json.bad-1" }, { kind: "unparseable" }]) {
    assert.doesNotMatch(bannerText(b), /[\\/]/, JSON.stringify(b));
  }
});

// ── The wiring ──

test("app.ts: the boot goes through bootState with IS_TAURI, and only inside Tauri does a failed boot refuse saves", () => {
  assert.match(app, /import \{ CLOUD_PROVIDERS, IS_TAURI, type AiServer \} from "\.\.\/core\/bridge\.ts";/);
  assert.match(app, /const first = bootState\(boot, IS_TAURI\);/, "the boot passes IS_TAURI");
  assert.match(app, /let refusing = boot === undefined && IS_TAURI;/, "a failed boot refuses saves only inside Tauri");
  assert.match(app, /write: \(next\) => \(refusing \? Promise\.resolve\(false\) : backend\.save\(next\)\)/, "the saver's write is refused while refusing");
});

test("app.ts: the boot's banner is pinned after the shell is built, with its words, kind and the buttons of its case", () => {
  assert.match(app, /function paintBootBanner\(\): void/);
  assert.match(app, /kind: bootBanner\.kind === "unparseable" \? "warn" : "err"/);
  assert.match(app, /actions: bootButtons\.map\(\(label\) => \(\{ label, onClick: \(\) => answerBoot\(label\) \}\)\)/);
  assert.match(app, /paintBootBanner\(\);\n/, "painted at boot");
});

test("app.ts: Try again reads Checked<Settings> through the backend; a read that works replaces the settings, clears the banner and the refusal, and syncs the pages", () => {
  const retry = innerFn(app, "tryAgain");
  assert.match(retry, /const r = await backend\.settingsRetryLoad\(\);/);
  assert.match(retry, /if \(!r\.ok \|\| !r\.value\) \{ shell\?\.banner\(\{ text: r\.ok \? "Your settings file still couldn't be read\." : r\.error \}\); return; \}/, "a failed read says so on the page strip");
  assert.match(retry, /settings = tidy\(\{ \.\.\.DEFAULT_SETTINGS, \.\.\.r\.value \}\);/);
  assert.match(retry, /saver\.echo\(settings\);/);
  assert.match(retry, /refusing = false;/);
  assert.match(retry, /clearBoot\(\);/);
  assert.match(retry, /forceValues\(\(\) => shell\?\.sync\(\), null\);/, "forced sync with no only");
});

test("app.ts: Start fresh asks the backend (which refuses while the file reads), clears the refusal and the banner, and writes nothing itself", () => {
  const fresh = innerFn(app, "startFresh");
  assert.match(fresh, /const r = await backend\.settingsStartFresh\(\);/);
  assert.match(fresh, /if \(!r\.ok\) \{ shell\?\.banner\(\{ text: r\.error \}\); return; \}/, "a refusal says why on the page strip");
  assert.doesNotMatch(fresh, /save\(|saver|ctx\.save/, "no save call in Start fresh");
  assert.match(fresh, /refusing = false;/);
  assert.match(fresh, /clearBoot\(\);/);
});

test("app.ts: Dismiss (the banner's last button) clears the banner through clearBoot and touches no file", () => {
  const answer = innerFn(app, "answerBoot");
  assert.match(answer, /else clearBoot\(\);/);
  assert.doesNotMatch(answer, /backend\./);
  const clear = innerFn(app, "clearBoot");
  assert.match(clear, /bootBanner = null;\s*bootButtons = \[\];\s*paintBootBanner\(\);/);
  assert.doesNotMatch(clear, /backend\./);
});

test("app.ts: the boot's settings come from bootState and the early island echo still wins over them", () => {
  assert.match(app, /settings = tidy\(\{ \.\.\.first\.settings, \.\.\.early \}\);/);
});

test("shell.ts: the pinned strip sits above the page strip, and select() never touches it", () => {
  assert.match(shell, /function pin\(b: Banner \| null\): void \{\s*fill\(pinned, b\);/);
  assert.match(shell, /h\("main", \{ class: "st-detail" \}, h\("div", \{ class: "st-top" \}, title, tabHost\), pinned, strip, scroll\)/);
  const select = innerFn(shell, "select");
  assert.doesNotMatch(select, /pinned|pin\(/, "a page change does not clear the pinned banner");
  assert.match(shell, /return \{ el, select, sync: \(\) => view\?\.sync\?\.\(\), current: \(\) => current, banner, pin, fit: \(\) => bar\?\.fit\(\) \}/);
  assert.match(shell, /pin\(b: Banner \| null\): void; fit\(\): void \}/, "the return type names pin and fit");
});

test("backend.ts: the retry and start fresh return the Bridge's Checked answers unchanged", () => {
  assert.match(backend, /settingsRetryLoad\(\): Promise<Checked<Settings>>;/);
  assert.match(backend, /settingsStartFresh\(\): Promise<Checked<void>>;/);
  assert.match(backend, /settingsRetryLoad: \(\) => Bridge\.settingsRetryLoad\(\),/);
  assert.match(backend, /settingsStartFresh: \(\) => Bridge\.settingsStartFresh\(\),/);
});

test("bridge.ts: the boot's settingsProblem, and the two checked commands by their Rust names", () => {
  assert.match(bridge, /export type SettingsProblem = \{ kind: "unreadable" \} \| \{ kind: "unparseable"; keptAs\?: string \};/);
  assert.match(bridge, /settingsProblem\?: SettingsProblem \| null;/);
  assert.match(bridge, /settingsRetryLoad: \(\) => callChecked<Settings>\("settings_retry_load"\),/);
  assert.match(bridge, /settingsStartFresh: \(\) => callChecked<void>\("settings_start_fresh"\),/);
});

test("the Rust side: the commands are registered, boot carries settings_problem, retry reads without a backup, and the gate is in save itself", () => {
  assert.match(lib, /^\s+settings_retry_load,$/m, "settings_retry_load is in the invoke handler list");
  assert.match(lib, /^\s+settings_start_fresh,$/m, "settings_start_fresh is in the invoke handler list");
  assert.match(lib, /settings_problem: Option<settings::LoadProblem>/);
  assert.match(lib, /settings::load_checked\(\)/, "run reads the file through load_checked");
  assert.match(lib, /let \(mut loaded, problem\) = settings::load_checked_read_only\(\);/, "retry never makes a backup");
  assert.match(lib, /let \(_, now\) = settings::load_checked_read_only\(\);\s*if let Some\(refusal\) = settings::start_fresh_refusal\(&current, &now, settings::settings_file_exists\(\)\)/, "start fresh checks the file first and says why");
  assert.match(settingsRs, /static SAVE_BLOCKED: AtomicBool/);
  assert.match(settingsRs, /pub fn save\(settings: &Settings\) -> std::io::Result<\(\)> \{\s*save_with\(&SAVE_BLOCKED,/);
});

test("the save gate has two ends and both are pinned: run() closes it from the boot problem, clear_problem is the only thing that opens it, and the commands call it in the right place", () => {
  // The start-up end: the very next statement after the load, so nothing can save before the gate knows the problem.
  assert.match(rustFn(lib, "run"), /let \(loaded, problem\) = settings::load_checked\(\);\s*settings::set_save_gate\(&problem\);/);
  // The opening end.
  assert.match(rustFn(lib, "clear_problem"), /set_save_gate\(&None\)/);
  assert.equal(lib.match(/clear_problem\(&shared\)/g)?.length, 2, "clear_problem is called from exactly two places");
  const retry = rustFn(lib, "settings_retry_load");
  const afterEarlyReturn = retry.indexOf("clear_problem(&shared)");
  assert.ok(retry.indexOf("if problem.is_some() {") >= 0 && retry.indexOf("if problem.is_some() {") < afterEarlyReturn, "Try again clears the problem only after the read came back clean");
  assert.match(retry, /if problem\.is_some\(\) \{\s*return Err\(/);
  const fresh = rustFn(lib, "settings_start_fresh");
  assert.ok(fresh.indexOf("start_fresh_refusal") >= 0 && fresh.indexOf("start_fresh_refusal") < fresh.indexOf("clear_problem(&shared)"), "Start fresh clears the problem only after the refusal check");
  // Try again moves the island the way a save would (M4).
  assert.match(retry, /let previous = std::mem::replace\(&mut \*shared\.settings\.lock\(\)\.unwrap\(\), loaded\.clone\(\)\);\s*clear_problem\(&shared\);\s*\/\/[^\n]*\n\s*apply_screen_change\(&app, &shared, &previous\.screen, &loaded\.screen\);/);
  assert.match(rustFn(lib, "save_settings"), /apply_screen_change\(&app, &shared, &previous\.screen, &settings\.screen\);/);
});

test("Launch at startup is changed before the file is written and told when refused: save_settings goes through save_in_step, with no eprintln", () => {
  const save = rustFn(lib, "save_settings");
  assert.match(save, /settings::save_in_step\(\s*was,\s*settings\.autostart,/);
  assert.match(save, /\.map_err\(String::from\)\?;/, "the fixed sentence goes to the page");
  assert.ok(!save.includes("eprintln!"), "no OS text on stderr");
  assert.ok(!save.includes("settings::commit(&shared.settings, settings.clone(), settings::save).map_err"), "the commit is inside the ordering, not before the startup change");
});

test("hooks_apply and store_learned write through settings::update and emit only after it wrote something (the Ok(Some) arm)", () => {
  for (const [name, text] of [["hooks_apply", rustFn(lib, "hooks_apply")], ["store_learned", rustFn(aiRs, "store_learned")]]) {
    assert.match(text, /settings::update\(&shared\.settings, change, (?:crate::)?settings::save\)/, `${name} goes through update`);
    assert.ok(!/settings::save\(&/.test(text), `${name} never saves outside update`);
    const emits = [...text.matchAll(/logged_emit\(/g)];
    assert.equal(emits.length, 1, `${name} emits once`);
    const arm = text.indexOf("Ok(Some(updated)) =>");
    assert.ok(arm >= 0 && emits[0].index > arm && text.indexOf("Ok(None)") > emits[0].index, `${name} emits in the Ok(Some(..)) arm`);
  }
});

test("a failed credential change is logged by name through secrets::logged, and the probes run off the main thread", () => {
  assert.match(rustFn(lib, "secret_set"), /secrets::logged\("set", &key, secrets::set\(&key, &value\)\)/);
  assert.match(rustFn(lib, "secret_clear"), /secrets::logged\("clear", &key, secrets::clear\(&key\)\)/);
});

test("main.ts and devseed.ts: ?bootproblem= reaches the dev backend, which reports it at boot and succeeds a retry after a click", () => {
  assert.match(main, /params\.get\("bootproblem"\)/);
  assert.match(devseed, /bootProblem: string \| null = null/);
  assert.match(devseed, /if \(v === "unreadable"\)/);
  assert.match(devseed, /settingsRetryLoad: async \(\) => \{\s*problem = null;\s*return \{ ok: true, value: info\.settings \};/);
  assert.match(devseed, /if \(problem\?\.kind === "unreadable"\) return false;/, "the dev store refuses saves while the file is unreadable");
});
