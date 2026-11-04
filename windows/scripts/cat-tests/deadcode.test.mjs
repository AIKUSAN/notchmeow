import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Names that were removed on purpose (spec §3, "Removed (dead code)") and must not come back. Every file of src/ and dev/ is read.
const root = fileURLToPath(new URL("../../", import.meta.url));
const sources = ["src", "dev"].flatMap((dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true, recursive: true })
  .filter((e) => e.isFile() && /\.(ts|css|html)$/.test(e.name)).map((e) => path.join(e.parentPath, e.name)));

const GONE = {
  "permanent emotes and miniEye": ["setPermanentEmote", "permanentEye", "EMOTE_EYE", "eyeOverride", "eyeOverrideUntil", "miniEye"],
  "the mailbox morph": ["animateMorph", "resetMorph", "slotHTarget", "slotHVel", "mouthRect", "MouthRect", "UploadEyeShape"],
  "the body colour": ["bodyColor", "hexToRGB"],
};

test("the removed names are not in any source file", () => {
  assert.ok(sources.length > 40, `${sources.length} files read`);
  for (const [why, names] of Object.entries(GONE)) for (const name of names) {
    const hits = sources.filter((f) => new RegExp(`\\b${name}\\b`).test(fs.readFileSync(f, "utf8"))).map((f) => path.relative(root, f));
    assert.deepEqual(hits, [], `${name} (${why})`);
  }
});

test("the cup eye, engine.gulp() and the engine's morph are gone too, and the cat's own hello wave stays", () => {
  const text = (rel) => fs.readFileSync(path.join(root, rel), "utf8");
  assert.doesNotMatch(text("src/cat/types.ts"), /"cup"/);
  assert.doesNotMatch(text("src/cat/renderer.ts"), /"cup"/);
  assert.doesNotMatch(text("src/upload/sequence.ts"), /"cup"|\bmorph\b/);
  assert.doesNotMatch(text("src/island/island.ts"), /\.gulp\(|\bmorph\b/);
  assert.doesNotMatch(text("src/cat/engine.ts"), /\bgulp\(\)|\bmorph\b/);
  assert.match(text("src/cat/engine.ts"), /greet\(\) \{/, "the contract's hello emote still plays through greet()");
});
