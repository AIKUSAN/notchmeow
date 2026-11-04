import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { REFUSAL_NOTES, classifyIngestError, noteSound } from "../../src/upload/refusal.ts";

const rust = (file) => fs.readFileSync(new URL(`../../src-tauri/src/${file}`, import.meta.url), "utf8");

test("the refusal texts are exactly the ones Rust gives for a refused file", () => {
  const fn = rust("ai/attachments.rs").match(/pub fn reject_message[\s\S]*?\n\}/)[0];
  const texts = [...fn.matchAll(/=> "([^"]+)"/g)].map((m) => m[1]);
  assert.equal(texts.length, 2, "one text for the size, one for the type");
  assert.deepEqual([...REFUSAL_NOTES].sort(), texts.sort());
  assert.match(rust("files.rs"), /Rejected\(reason\)[\s\S]*reject_message\(reason\)/, "ingest returns those texts for a refused file");
});

test("a refusal is told from every other way ingest can fail, however the error arrives", () => {
  for (const note of REFUSAL_NOTES) for (const err of [note, `Error: ${note}`, new Error(note)]) {
    assert.deepEqual(classifyIngestError(err), { message: note, refused: true }, String(err));
  }
  // The other failures of files::ingest, and what the browser gives when there is no Tauri.
  for (const other of ["Folders can't be dropped yet.", "cannot read C:\\a.txt: Access is denied. (os error 5)", "cannot copy: There is not enough space on the disk. (os error 112)", "not running inside NotchMeow", "", "I can't read this kind of file. Really."]) {
    const c = classifyIngestError(other);
    assert.equal(c.refused, false, other);
    assert.equal(c.message, other);
  }
  for (const odd of [undefined, null, 42, {}, ["I can't read this kind of file."]]) assert.equal(typeof classifyIngestError(odd).message, "string");
  assert.equal(classifyIngestError(undefined).refused, false);
  assert.ok(rust("files.rs").includes("Folders can't be dropped yet."), "a folder still gets its own text");
});

test("the note of a refusal is silent (the cat's annoyed at the gag is its only sound); any other failure keeps its error sound", () => {
  assert.equal(noteSound(true), null);
  assert.equal(noteSound(false), "error");
  for (const note of REFUSAL_NOTES) assert.equal(noteSound(classifyIngestError(note).refused), null, note);
  for (const other of ["Folders can't be dropped yet.", "cannot copy: disk full", "not running inside NotchMeow", undefined]) {
    assert.equal(noteSound(classifyIngestError(other).refused), "error", String(other));
  }
});
