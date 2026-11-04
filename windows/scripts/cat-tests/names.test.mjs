import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// The upstream character's name is gone from the Windows and Linux app: code, comments, scripts, the README and the manifests. Historical plans,
// specs and the git history are not swept. The word is built from two halves, so that this file does not contain it.
const NAME = new RegExp("mo" + "chi", "i");
const root = fileURLToPath(new URL("../../", import.meta.url));
const SKIP = new Set(["node_modules", "target", "dist", "release", "gen", ".playwright-cli"]);
const BINARY = /\.(png|ico|icns|wav|mp3|woff2?|bin|exe|dll|node|zip|gz)$/i;

function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else yield p;
  }
}

test("no file of windows/, and no file name, says the old character's name", () => {
  const hits = [];
  let read = 0;
  for (const f of walk(root)) {
    const rel = path.relative(root, f);
    if (NAME.test(rel)) hits.push(`${rel} (its name)`);
    if (BINARY.test(f)) continue;
    read++;
    if (NAME.test(fs.readFileSync(f, "utf8"))) hits.push(rel);
  }
  assert.ok(read > 100, `${read} files read`);
  assert.deepEqual(hits, []);
});
