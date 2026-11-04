import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the site's entry runs the app's own engine and loop, stops by the rules above, and keeps nothing and sends nothing", () => {
  const main = source("src/site/main.ts");
  assert.match(main, /import \{ BotEngine \} from "\.\.\/cat\/engine\.ts"/);
  assert.match(main, /import \{ drawCat, stillView \} from "\.\.\/cat\/renderer\.ts"/);
  assert.match(main, /new VisibleLoop\(/);
  assert.match(main, /visible: \(\) => animates\(page\)/);
  for (const need of ["prefers-reduced-motion", "visibilitychange", "IntersectionObserver", 'emote("happy")', "cursorLook("]) assert.ok(main.includes(need), need);
  assert.doesNotMatch(main, /\bfetch\s*\(|localStorage|sessionStorage|document\.cookie|XMLHttpRequest|sendBeacon|AudioContext/);
  const config = source("vite.site.config.ts");
  for (const need of ["src/site/main.ts", 'entryFileNames: "cats.js"', 'assetFileNames: "cats[extname]"', "src/site/silent.ts", '"../docs/assets"']) assert.ok(config.includes(need), need);
});
