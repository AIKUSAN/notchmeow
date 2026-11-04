// Shared by the sidekick checks: the fixture loader. The fixtures in tests/fixtures/sidekick/ are generated from shared/sidekick-core.js (docs/SIDEKICK-CONTRACT.md).
import fs from "node:fs";

/** One fixture file of tests/fixtures/sidekick/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/sidekick/${name}`, import.meta.url), "utf8"));

/** A file of windows/src/, as text (for the wiring checks that pin where the app calls the pure parts). */
export const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
