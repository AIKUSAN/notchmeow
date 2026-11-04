import test from "node:test";
import assert from "node:assert/strict";
import { code } from "./util.mjs";

// The ?dev Projects panel (Task 8 of P-tauri): the Windows/Linux twin of the Mac's render and fake-event tools. It has its own model on its own clock, its frames are the
// shipped views, it runs no loop and no timer of its own, and it never touches the app's Projects state or the skewed clock.

const dev = code("projects/devprojects.ts"), mount = code("cat/dev.ts");

test("cat/dev.ts mounts the Projects panel once, after the Link panel", () => {
  assert.match(mount, /import \{ mountProjectsDev \} from "\.\.\/projects\/devprojects\.ts";/);
  assert.equal((mount.match(/mountProjectsDev\(root, wrap\);/g) ?? []).length, 1);
  assert.ok(mount.indexOf("mountProjectsDev(root, wrap);") > mount.indexOf("mountLinkDev(root, wrap);"));
});

test("the panel builds its own ProjectsModel on its own clock", () => {
  assert.equal((dev.match(/new ProjectsModel\(/g) ?? []).length, 1);
  assert.match(dev, /const clock = \(\) => T0 \+ offset;/);
  assert.match(dev, /new ProjectsModel\(\{ home: HOME, now: clock \}\)/);
  assert.doesNotMatch(dev, /State\.projects\b/);
  assert.doesNotMatch(dev, /\bSkew\b/);
});

test("the panel runs no loop and no timer of its own", () => {
  assert.doesNotMatch(dev, /setInterval|requestAnimationFrame|setTimeout/);
});

test("every scenario gets a button, named from the scenario table", () => {
  assert.match(dev, /import \{ PROJECT_SCENARIOS \} from "\.\/scenarios\.ts";/);
  assert.match(dev, /Object\.keys\(PROJECT_SCENARIOS\)/);
});

test("the panel has the ages, the layout switches, the pin and the clear buttons", () => {
  for (const label of ["+10 min", "+30 min", "+2 h", "Claude only", "With other agents", "Two cats", "Pin the first", "Clear"])
    assert.ok(dev.includes(`"${label}"`), label);
});

test("the frames are the shipped views, not copies", () => {
  const imp = dev.match(/import \{([^}]*)\} from "\.\.\/views\/projects\.ts";/);
  assert.ok(imp, "one import from views/projects.ts");
  for (const name of ["buildBigCard", "buildProjectGrid", "buildTitleCap", "buildClaudePanel", "buildProjects", "ProjectPeek"])
    assert.match(imp[1], new RegExp(`\\b${name}\\b`));
});

test("the five frames are drawn at their sizes, and the badge takes the shelf badge's rule and place", () => {
  const sizes = [...dev.matchAll(/\bstage\(\s*(\d+),\s*(\d+)/g)].map((m) => `${m[1]}x${m[2]}`);
  assert.deepEqual(sizes, ["640x160", "640x252", "640x240", "640x160", "288x32"]);
  assert.match(dev, /from "\.\.\/shelf\/badge\.ts"/);
  for (const name of ["badgeShown", "badgeLabel", "badgePlace"]) assert.match(dev, new RegExp(`\\b${name}\\(`));
  assert.match(dev, /badgePlace\(\s*288,\s*32\s*\)/);
});

test("the panel is titled Projects and says what it is", () => {
  assert.match(dev, /<h2[^>]*>Projects<\/h2>/);
  assert.ok(dev.includes("The Projects views fed by a registry in memory that follows the contract: pick a scenario, age it, switch the layout, pin. Nothing here is the app's own state."));
});

test("the panel logs fixed words for its actions and never reads a folder path", () => {
  assert.ok(dev.includes('"open screen"'));
  assert.match(dev, /`jump \$\{/);
  assert.doesNotMatch(dev, /cwdOf/);
});

test("the stand-in big cat fades while its overview's peek shows: the peek's own source says so, and the cat's opacity follows it", () => {
  assert.match(dev, /new ProjectPeek\(own, leftCard, 108\)/, "the overview's peek is built on its own source");
  assert.match(dev, /peek: \(id\) => \{\s*model\.setPeeking\(id\);\s*peekOn = id !== null;\s*fadeCat\(\);/, "a peek's show or hide sets the flag and fades the cat");
  assert.match(dev, /const v = peekOn \? "0" : "1";/);
  assert.match(dev, /cat\.el\.style\.opacity !== v\) cat\.el\.style\.opacity = v;/, "compare before assign");
  assert.doesNotMatch(dev, /setTimeout|setInterval|requestAnimationFrame/);
});
