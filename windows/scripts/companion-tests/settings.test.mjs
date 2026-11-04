import test from "node:test";
import assert from "node:assert/strict";
import { cleanCompanionSettings } from "../../src/companion/core.ts";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";

test("a fresh install has the companion's defaults in the app's settings too", () => {
  assert.deepEqual(DEFAULT_SETTINGS.companion, cleanCompanionSettings(null));
  assert.equal(DEFAULT_SETTINGS.companion.humor, "little");
  assert.equal(DEFAULT_SETTINGS.companion.seeSessions, true);
});
