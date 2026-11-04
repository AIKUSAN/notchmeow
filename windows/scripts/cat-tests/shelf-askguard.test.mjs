import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The Ask copy's success path against a Shelf drop that came after it (G1). The island needs the DOM and the bridge to run, so these are source pins, as in
// shelf-drop.test.mjs. A copy is judged by its drop token and by the token of the latest Shelf drop: a Shelf drop silences it, a newer Ask drop only its attachment.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");
const between = (s, a, b) => s.slice(s.indexOf(a), s.indexOf(b));
// The Ask copy: from the copy's start to its catch.
const copy = () => between(isl, "void ingest(path)", "      .catch((err) => {");
// What runs before the approve chime on the success path.
const beforeChime = () => copy().slice(0, copy().indexOf('Sound.play("approve");'));
// What runs from the approve chime to the attachment.
const chimeToAttach = () => copy().slice(copy().indexOf('Sound.play("approve");'), copy().indexOf("State.droppedFile = { name: file.name"));

test("an Ask copy that lands after a Shelf drop plays no chime and attaches nothing: the success path returns first, on the Shelf token", () => {
  assert.match(beforeChime(), /\.then\(async \(file\) => \{[\s\S]*if \(drop <= this\.shelfDropToken\) return;/, "the Shelf check comes before the chime");
  assert.doesNotMatch(beforeChime(), /State\.pendingAttachment|State\.promptContext|State\.droppedFile/, "nothing is attached before the check");
  assert.equal((beforeChime().match(/if \(/g) ?? []).length, 1, "the Shelf token is the only check before the chime");
});

test("an Ask drop alone is unchanged: its copy takes the token, then the chime, the attachment and the reader, in the same order", () => {
  assert.match(isl, /private swallow\(path: string, ingest: \(path: string\) => Promise<DroppedFile> = \(p\) => Bridge\.ingestFile\(p\)\) \{[\s\S]*?const drop = \+\+this\.dropCount;[\s\S]*?void ingest\(path\)/, "a single Ask takes its token before the copy");
  assert.match(copy(), /Sound\.play\("approve"\);[\s\S]*?State\.droppedFile = \{ name: file\.name, path: file\.path \};\s*State\.promptContext = \{ kind: "file", name: file\.name, path: file\.path \};\s*\/\/ The inbox copy goes with the next message, whichever turn that is\.\s*State\.pendingAttachment = file\.path;\s*State\.notify\(\);\s*const reader = await Bridge\.aiResolve\("files"\);\s*State\.dropReader = reader\?\.reader \?\? null;/);
});

test("Ask then Ask: the first copy chimes but attaches nothing (a newer drop owns the attachment), and the second copy chimes and attaches", () => {
  const shelfGuard = beforeChime().indexOf("if (drop <= this.shelfDropToken) return;");
  const chime = copy().indexOf('Sound.play("approve");');
  const attachGuard = copy().indexOf("if (drop !== this.dropCount) return;");
  const attach = copy().indexOf("State.pendingAttachment = file.path;");
  assert.ok(shelfGuard >= 0 && shelfGuard < chime, "a Shelf drop turns the copy away before the chime");
  assert.ok(chime < attachGuard && attachGuard < attach, "the chime comes first; the attachment sits behind the no-newer-drop check");
  assert.match(isl, /private swallow\(path: string, ingest: \(path: string\) => Promise<DroppedFile> = \(p\) => Bridge\.ingestFile\(p\)\) \{[\s\S]*?const drop = \+\+this\.dropCount;/, "each Ask takes its own token");
  assert.doesNotMatch(beforeChime(), /askBusy|copying|pendingCopy|busy/, "no flag that would block the second Ask: the newest token is the only one that runs");
});

test("the chime is not gated by the newer-drop token: the Shelf token is its own field, set by a Shelf drop, and the newer-drop check guards only the attachment", () => {
  const shelf = isl.match(/private shelfDrop\(paths: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];
  assert.match(isl, /private shelfDropToken = -1;/, "the latest Shelf drop's token starts at none");
  assert.match(shelf, /this\.shelfDropToken = this\.dropCount;/, "a Shelf drop records its token");
  assert.doesNotMatch(beforeChime(), /drop !== this\.dropCount/, "the chime is not gated by drop === this.dropCount");
  assert.match(chimeToAttach(), /if \(drop !== this\.dropCount\) return;/, "the attachment is guarded by the newer-drop token");
});
