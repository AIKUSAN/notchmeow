// The fixture loader of the Companion checks. The fixtures in tests/fixtures/companion/ are generated from shared/companion-core.js (docs/COMPANION-CONTRACT.md).
import fs from "node:fs";

/** One fixture file of tests/fixtures/companion/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/companion/${name}`, import.meta.url), "utf8"));
