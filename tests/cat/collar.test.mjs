import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const STYLES = ['tag', 'band', 'kerchief']; // the three that draw something; 'off' draws nothing
const finite = v => (Array.isArray(v) ? v.every(finite) : v && typeof v === 'object' ? Object.values(v).every(finite) : typeof v === 'number' ? Number.isFinite(v) : true);
const onHead = (pts, p, R, k = 1.02) => pts.every(([x, y]) => (x / (p.rx * R)) ** 2 + (y / (p.ry * R)) ** 2 <= k * k);

test('the four style IDs are frozen, in order, and an unknown stored one falls back to off', () => {
  assert.deepEqual(core.COLLAR_STYLES, ['tag', 'band', 'kerchief', 'off']);
  for (const id of core.COLLAR_STYLES) assert.equal(core.collarStyleOf(id), id);
  for (const bad of ['scarf', 'Tag', ' tag', 'tag ', '', 'bowtie', null, undefined, 7, true, {}, ['tag']]) assert.equal(core.collarStyleOf(bad), 'off', String(bad));
});

test('off draws nothing, and an unknown style is off, never a throw', () => {
  const p = core.PRESETS.momo;
  for (const style of ['off', 'scarf', '', null, undefined, 7]) assert.equal(core.collarGeometry(p, pose(), 40, style), null, String(style));
});

test('the device-pixel floors: band 3, tag 6, neckerchief 7 wide and 5 deep, at Ø12 to Ø20 and any pixel density', () => {
  assert.deepEqual(core.COLLAR_MIN, { band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5 });
  for (const dpr of [1, 2, 3]) for (const D of [12, 16, 20]) for (const style of STYLES) {
    const g = core.collarGeometry(core.PRESETS.shrimpy, pose(), D, style, { dpr });
    if (style !== 'kerchief') assert.ok(g.width * dpr >= core.COLLAR_MIN.band - 1e-9, `band ${g.width * dpr} at D${D} dpr${dpr}`);
    if (style === 'tag') assert.ok(g.tag.r * 2 * dpr >= core.COLLAR_MIN.tag - 1e-9, `tag at D${D} dpr${dpr}`);
    if (style === 'kerchief') {
      const xs = g.kerchief.pts.map(q => q[0]);
      assert.ok((Math.max(...xs) - Math.min(...xs)) * dpr >= core.COLLAR_MIN.kerchiefW - 1e-9, `kerchief width at D${D} dpr${dpr}`);
      assert.ok((g.kerchief.apex[1] - Math.max(...g.kerchief.pts.map(q => q[1]))) * dpr >= core.COLLAR_MIN.kerchiefDrop - 1e-9, `kerchief drop at D${D} dpr${dpr}`);
    }
  }
});

test('each style has exactly its own parts', () => {
  const g = style => core.collarGeometry(core.PRESETS.momo, pose(), 40, style);
  assert.deepEqual(Object.keys(g('tag')), ['style', 'R', 'width', 'band', 'tag']);
  assert.deepEqual(Object.keys(g('band')), ['style', 'R', 'width', 'band']);
  assert.deepEqual(Object.keys(g('kerchief')), ['style', 'R', 'kerchief']);
  assert.equal(g('tag').band.length, 26);
  assert.ok(g('kerchief').kerchief.pts.length > 4);
  for (const style of STYLES) assert.equal(g(style).style, style);
});

test('the collar is drawn in the front pass, in the one slot between the folded ears and the whiskers', () => {
  assert.equal(core.COLLAR_PASS, 'front');
  const front = core.PASSES[core.COLLAR_PASS];
  assert.equal(front.indexOf('whiskers'), front.indexOf('foldEars') + 1);
});

test('large sizes scale with the head: the band a tenth of R, the tag 0.16 R, the neckerchief about 0.34 R deep', () => {
  const p = core.PRESETS.momo, at = style => core.collarGeometry(p, pose(), 66, style);
  near(at('band').width / at('band').R, .1);
  near(at('tag').tag.r / at('tag').R, .16);
  const k = at('kerchief'), drop = k.kerchief.apex[1] - Math.max(...k.kerchief.pts.map(q => q[1]));
  assert.ok(drop >= .34 * k.R - 1e-9 && drop < .36 * k.R, `the drop is ${drop / k.R} R`); // 0.34 R below the chin, plus the gap between the chin and the nearest sampled point
});

test('every coat, style, pose and size, at either pixel density: the collar is finite and stays on the head', () => {
  for (const p of Object.values(core.PRESETS)) for (const style of STYLES) for (const s of [pose(), pose({ yaw: .6 }), pose({ yaw: -.6, pitch: .4 }), pose({ pitch: -.3 })]) for (const D of [12, 20, 28, 66]) for (const dpr of [1, 2]) {
    const g = core.collarGeometry(p, s, D, style, { dpr });
    assert.ok(finite(g), `${p.name} ${style} D${D}`);
    assert.ok(onHead(g.band || g.kerchief.pts, p, g.R), `${p.name} ${style} D${D} dpr${dpr}`);
  }
});

test('a head of width 0, or a bad pixel ratio, never produces NaN', () => {
  for (const style of STYLES) {
    assert.ok(finite(core.collarGeometry(core.PRESETS.shrimpy, pose(), 0, style)), `${style} at Ø0`);
    const two = core.collarGeometry(core.PRESETS.momo, pose(), 20, style, { dpr: 2 });
    for (const dpr of [NaN, 0, -1, undefined, null]) assert.deepEqual(core.collarGeometry(core.PRESETS.momo, pose(), 20, style, { dpr }), two, `${style} dpr ${dpr}`);
  }
});

test('the tag sits at centre front at rest and follows the face when the head turns', () => {
  const p = core.PRESETS.shrimpy, rest = core.collarGeometry(p, pose(), 66, 'tag'), turned = core.collarGeometry(p, pose({ yaw: .6 }), 66, 'tag');
  assert.ok(Math.abs(rest.tag.x) < 1e-9 && rest.tag.y > 0);
  assert.ok(turned.tag.x > rest.tag.x + 1, 'the tag moves toward the side the face turned to');
  const k = core.collarGeometry(p, pose(), 66, 'kerchief');
  assert.ok(Math.abs(k.kerchief.apex[0]) < 1e-9, 'the neckerchief points straight down at rest');
});

test('the pose is not touched and the same input gives the same output', () => {
  const s = pose({ yaw: .3 }), before = JSON.stringify(s);
  const a = core.collarGeometry(core.PRESETS.momo, s, 28, 'kerchief'), b = core.collarGeometry(core.PRESETS.momo, s, 28, 'kerchief');
  assert.equal(JSON.stringify(s), before);
  assert.deepEqual(a, b);
});

test('collar-cases.json: every case replays from its own inputs, and the style IDs and floors match', () => {
  const c = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/collar-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(c.styles, core.COLLAR_STYLES);
  assert.deepEqual(c.min, core.COLLAR_MIN);
  for (const r of c.resolve) assert.equal(core.collarStyleOf(r.id), r.style, String(r.id));
  assert.ok(c.cases.length >= 100);
  for (const k of c.cases) {
    const p = k.kitten ? core.kittenOf(core.PRESETS[k.cat]) : core.PRESETS[k.cat];
    const got = JSON.parse(JSON.stringify(core.collarGeometry(p, pose(k.pose), k.D, k.style, { dpr: k.dpr })));
    assert.deepEqual(compare(got, k.out), [], `${k.cat} ${k.style} D${k.D} dpr${k.dpr}`);
  }
  for (const style of STYLES) for (const D of [12, 20, 66]) for (const dpr of [1, 2]) assert.ok(c.cases.some(k => k.style === style && k.D === D && k.dpr === dpr), `${style} D${D} dpr${dpr} is in the fixture`);
  assert.ok(c.cases.some(k => k.style === 'off' && k.out === null), 'off is in the fixture');
});

test('geometry-cases.json: collarPass names the pass of the collar, and passes is still the line A-0 wrote', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.equal(g.collarPass, core.COLLAR_PASS);
  assert.ok(g.collarPass in g.passes);
  assert.deepEqual(g.passes, core.PASSES);
  assert.ok(!JSON.stringify(g.passes).includes('collar'), 'the collar is not added to passes: fixtures change only by addition');
});
