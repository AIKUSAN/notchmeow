// Privacy pins for the Settings window's new files (Task 5): no real user or machine name in any file, picture or sample, and the dev sample reads nothing from this computer.
// Samples use the home folder C:\Users\sample. The script writes nowhere but its --out folder and its throwaway profile.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const NAME = /\b(ike|lorenz|tazan)\b/i;
const RAILLE = /raill/i;
const settingsFiles = fs.readdirSync(new URL("../../src/settings/", import.meta.url)).filter((f) => f.endsWith(".ts")).map((f) => `src/settings/${f}`);
const files = ["src/settings/devseed.ts", "src/settings/devpanel.ts", "scripts/render-settings.sh", "src/companion/devcompanion.ts", "scripts/render-companion.sh", ...settingsFiles];

test("no real user name in the Settings files, the dev seed, the dev panel or the render script", () => {
  for (const f of files) {
    const text = read(f);
    assert.doesNotMatch(text, NAME, f);
    assert.doesNotMatch(text, RAILLE, f);
  }
});

test("the dev seed uses the sample home folder and reads nothing from this computer", () => {
  const seed = read("src/settings/devseed.ts");
  assert.ok(seed.includes("C:\\\\Users\\\\sample"), "the sample home is C:\\Users\\sample");
  for (const banned of ["process.env", "os.", "navigator.userAgent", "homedir"]) assert.ok(!seed.includes(banned), banned);
});

test("the render script writes only to its --out folder and its throwaway profile", () => {
  const script = read("scripts/render-settings.sh");
  assert.ok(!/\$HOME|~\//.test(script), "no home-folder path in the script");
  assert.ok(!/\.claude|\.gemini|Application Support|AppData/.test(script), "no agent or app-data folder");
  assert.ok(script.includes("mktemp -d"), "the profile is a throwaway folder");
});
