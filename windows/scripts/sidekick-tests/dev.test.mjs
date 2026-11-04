import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { source } from "./util.mjs";

test("the scripted runs are for the dev server only: main.ts loads them behind import.meta.env.DEV and a dynamic import, nothing else imports them, and a release build holds none of their words", () => {
  const main = source("main.ts");
  const at = main.indexOf('import("./sidekick/dev")');
  assert.ok(at > 0);
  assert.ok(main.lastIndexOf("if (import.meta.env.DEV) {", at) > main.indexOf("Hub.sk = new Sidekick("), "inside a DEV block, after the Sidekick exists");
  assert.equal(main.split("sidekick/dev").length - 1, 1);
  for (const f of fs.readdirSync(new URL("../../src/", import.meta.url), { recursive: true })) {
    if (typeof f === "string" && f.endsWith(".ts") && !f.endsWith("main.ts") && !f.endsWith("sidekick/dev.ts")) assert.doesNotMatch(fs.readFileSync(new URL(`../../src/${f}`, import.meta.url), "utf8"), /sidekick\/dev"|sidekick\/dev\.ts"/, f);
  }
  const dev = source("sidekick/dev.ts");
  assert.match(dev, /export function sidekickScenarios\(/);
  for (const run of ["recap", "loop", "errors", "waiting", "quiet", "card", "agents", "skew"]) assert.ok(dev.includes(`${run}(`), run);
});

test("the clock knob is always 0 in the app: only the dev runs move it", () => {
  assert.match(source("sidekick/appenv.ts"), /export const Skew = \{ ms: 0 \};/);
  const movers = fs.readdirSync(new URL("../../src/", import.meta.url), { recursive: true }).filter((f) => typeof f === "string" && f.endsWith(".ts") && /Skew\.ms\s*(\+|=)/.test(fs.readFileSync(new URL(`../../src/${f}`, import.meta.url), "utf8")));
  assert.deepEqual(movers.map((f) => f.replaceAll("\\", "/")), ["sidekick/dev.ts"]);
});
