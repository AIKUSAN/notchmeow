import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Tuck the island away, Windows and Linux: where the island page, the Settings card and the Rust settings call the rule (windows/src/island/tuckaway.ts), pinned as source text.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const count = (text, needle) => text.split(needle).length - 1;

test("the hook handler starts the count: every hook event that the app takes (touchPill's place on the Mac), after the paused and chat returns", () => {
  const hooks = source("island/hooks.ts");
  assert.equal(count(hooks, "island.agentActivity();"), 1, "one call");
  const at = hooks.indexOf("island.agentActivity();");
  assert.ok(at > hooks.indexOf("if (State.paused)") && at > hooks.indexOf("handleChatHook(island, payload);") && at < hooks.indexOf("Hub.sk?.hook(payload);") + 200, "after the paused and chat returns, with the sidekick's feed");
});

test("the island page: the setting is handed to the state machine at start and on apply; live is read from the pills' states only", () => {
  const island = source("island/island.ts");
  assert.equal(count(island, "this.fsm.tuckAway = State.settings.tuckAway;"), 2, "in wireFsm and applySettings");
  assert.match(island, /State\.subscribe\(\(\) => this\.fsm\.setLive\(isLive\(State\.tasks\.map\(\(t\) => t\.state\)\)\)\);/, "the live rule, inlined, reads the pills' states only");
  assert.doesNotMatch(island, /tuckLive/, "no separate helper any more");
  assert.doesNotMatch(island, /ledger\.live\.length/, "the sidekick's ledger is not read for the live rule");
  assert.match(island, /agentActivity\(\) \{|agentActivity\(\): void \{/, "the island exposes the activity to the hook handler");
  assert.equal(count(island, "this.fsm.setLive("), 1, "setLive is called from one place");
});

test("a click on the island restarts the count for the primary button only: the press passes whether it is button 0, and userInteracted starts with agentActivity for it", () => {
  const fsm = source("island/fsm.ts");
  assert.match(fsm, /userInteracted\(primary = true\) \{\s*if \(primary\) this\.agentActivity\(\);[^\n]*\n\s*if \(!this\.byHover\) return;/);
  assert.match(source("island/island.ts"), /this\.fsm\.userInteracted\(e\.button === 0\);/, "the island's press passes the button");
});

test("the shelf's drag-out and send hold the island with their own flags; the alert pin is no longer written for them", () => {
  const island = source("island/island.ts");
  assert.equal(count(island, 'this.fsm.setShelfHold("drag", true);'), 1);
  assert.equal(count(island, 'this.fsm.setShelfHold("drag", false);'), 1);
  assert.equal(count(island, 'this.fsm.setShelfHold("send", on)'), 1, "the send's hold goes through SendHold, the one place the send is set");
  assert.equal(count(island, "this.fsm.pinned = State.isPinned;"), 1, "only the alert's own pin (alert()) is written from the user's pin");
  assert.match(source("island/fsm.ts"), /get held\(\): boolean \{\s*return this\.pinnedFlag \|\| this\.shelfHolds\.drag \|\| this\.shelfHolds\.send;/);
});

test("the Settings hint names the click and no longer says a session is open; the island's comment says what a live change is", () => {
  const settings = source("settings/general.ts");
  const island = source("island/island.ts");
  assert.match(settings, /this long has passed since the last hook event, alert or click on the island\."/);
  assert.doesNotMatch(settings, /no session is open/);
  assert.doesNotMatch(island, /a session opens or ends/);
});

test("the dead absence row is gone: no 'Hide after … min without movement' setting, its field, or its default", () => {
  const settings = source("settings/general.ts");
  const state = source("core/state.ts");
  const rust = fs.readFileSync(new URL("../../src-tauri/src/settings.rs", import.meta.url), "utf8");
  assert.doesNotMatch(settings, /without movement|absenceInterval/);
  assert.doesNotMatch(state, /absenceInterval/);
  assert.doesNotMatch(rust, /pub absence_interval|absence_interval: 180\.0/);
});

test("the Settings card: a select in General with the five choices, saved with the others", () => {
  const settings = source("settings/general.ts");
  assert.match(settings, /row\("Tuck the island away", tuck, "The compact island/);
  assert.match(settings, /\(v\) => void ctx\.save\(\{ \.\.\.ctx\.settings\(\), tuckAway: v as TuckChoice \}\),?/);
  for (const [value, text] of [["never", "Never"], ["1", "After 1 min"], ["5", "After 5 min"], ["15", "After 15 min"], ["30", "After 30 min"]]) {
    assert.match(settings, new RegExp(`\\["${value}", "${text}"\\]`), value);
  }
});

test("the state: the Settings type has tuckAway, defaulting to never", () => {
  const state = source("core/state.ts");
  assert.match(state, /tuckAway: TuckChoice;/);
  assert.match(state, /tuckAway: "never",/);
});

test("the Rust twin: the setting is a string on Settings, defaults to never, is cleaned on load and on save", () => {
  const rust = fs.readFileSync(new URL("../../src-tauri/src/settings.rs", import.meta.url), "utf8");
  assert.match(rust, /pub tuck_away: String,/);
  assert.match(rust, /tuck_away: default_tuck_away\(\),/);
  assert.match(rust, /settings\.tuck_away = clean_tuck_away\(&settings\.tuck_away\);/);
});
