import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CompanionCore as C } from "../../src/companion/core.generated.ts";
import * as K from "../../src/companion/core.ts";
import { load } from "./util.mjs";

// Every group of every fixture of tests/fixtures/companion/ is replayed here. A group that is not listed below fails the file (a new group must be added on purpose),
// and each group must have at least one row. A failing row names itself through c.name.

const FIXTURES = new URL("../../../tests/fixtures/companion/", import.meta.url);

/** A group's replay: `run(row)` gives the actual answer, `want(row)` what the row says it must be (c.expect unless the group says otherwise). */
const group = (run, want = (c) => c.expect) => ({ run, want });

/** fixture file -> group -> replay. The generated copy (CompanionCore) answers the groups the relaunch does not type; core.ts answers the rest. */
const REPLAY = {
  "conversation-cases.json": {
    title: group((c) => K.titleOf(c.text)),
    clean: group((c) => K.conversationClean(c.raw)),
    keep: group((c) => K.conversationsKeep(c.entries)),
  },
  "daylog-cases.json": {
    add: group((c) => C.dayLogAdd(c.memory, c.day, c.project)),
  },
  "memory-cases.json": {
    read: group((c) => C.memoryRead(c.text, c.today)),
    text: group((c) => C.memoryText(c.memory)),
    add: group((c) => C.noteAdd(c.memory, c.section, c.text, c.day, c.source)),
    edit: group((c) => C.noteEdit(c.memory, c.index, c.text)),
    remove: group((c) => C.noteRemove(c.memory, c.index)),
    block: group((c) => C.memoryPromptBlock(c.memory, c.maxTokens)),
  },
  "note-cases.json": {
    check: group((c) => C.noteCheck(c.text)),
    offers: group((c) => C.rememberOffers(c.text)),
  },
  "prompt-cases.json": {
    cases: group((c) => K.promptOf({ ...c.input })),
    pc: group((c) => K.promptOf({ ...c.input })),
  },
  "quick-cases.json": {
    request: group((c) => K.quickRequest(c.kind, c.text)),
    result: group((c) => K.quickResultClean(c.kind, c.reply)),
    pc: group((c) => K.quickRequest(c.kind, c.text, c.device)),
  },
  "quiet-cases.json": {
    quiet: group((c) => K.companionQuiet(c.input)),
    mood: group((c) => K.moodHint(c.state)),
    tokens: group((c) => K.memoryTokensFor(c.placement, c.contextTokens)),
  },
  "recap-cases.json": {
    step: group((c) => C.dailyRecapStep(c.state, c.event, c.ctx)),
    text: group((c) => C.dailyRecapText(c.input)),
    polish: group((c) => C.acceptPolish(c.line, c.template)),
    dismiss: group((c) => [C.recapDismiss(c.count), C.recapMuted(c.count)], (c) => [c.next, c.muted]),
  },
  "rightnow-cases.json": {
    cases: group((c) => K.rightNowOf(c.view)),
    notice: group((c) => K.cloudNotice(c.provider)),
    needs: group((c) => K.needsCloudNotice(c.input)),
  },
  "settings-cases.json": {
    cases: group((c) => K.cleanCompanionSettings(c.raw)),
  },
};

for (const [file, groups] of Object.entries(REPLAY)) {
  test(`${file}: every group replays, and no group is missing from the replay`, () => {
    const f = load(file);
    const arrays = Object.keys(f).filter((k) => Array.isArray(f[k]));
    assert.deepEqual(arrays.sort(), Object.keys(groups).sort(), `${file} groups`);
    for (const [name, g] of Object.entries(groups)) {
      const rows = f[name];
      assert.ok(rows.length > 0, `${file} group "${name}" is not empty`);
      for (const c of rows) assert.deepEqual(g.run(c), g.want(c), `${file} ${name}: ${c.name}`);
    }
  });
}

test("the replay covers every fixture file of the contract", () => {
  const files = fs.readdirSync(FIXTURES).filter((n) => n.endsWith(".json")).sort();
  assert.deepEqual(files, Object.keys(REPLAY).sort());
});
