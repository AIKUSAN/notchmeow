import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fixture = () => JSON.parse(fs.readFileSync(new URL('../fixtures/cat/wardrobe-cases.json', import.meta.url), 'utf8'));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) <= 1e-9, `${msg}: ${a} vs ${b}`);
const REST = core.newPose(), TURNED = { ...core.newPose(), yaw: .6, pitch: .15 };
const STRIPS = [[32, 20], [24, 18]]; // [height of the strip the cat sits in, head width]: the notch, and a screen without one
const finite = v => typeof v === 'number' ? Number.isFinite(v) : Array.isArray(v) ? v.every(finite) : v && typeof v === 'object' ? Object.values(v).every(finite) : true;
test('the frozen values: 18 selection IDs in the grid order, 16 of them drawn, five rows of the grid, the roles', () => {
  assert.deepEqual(core.OUTFIT_IDS, ['auto', 'none', 'partyhat', 'santahat', 'witchhat', 'bunnyears', 'sunglasses', 'beanie', 'bow', 'scarf', 'roundglasses', 'crown', 'bell', 'bandana', 'fishclip', 'flower', 'shrimpclip', 'blossomclip']);
  assert.deepEqual(core.OUTFIT_DRAWN, core.OUTFIT_IDS.slice(2));
  assert.deepEqual(core.OUTFIT_GROUPS.flatMap(g => g.ids), core.OUTFIT_IDS, 'the groups hold every ID once, in the order of the IDs');
  assert.deepEqual(core.OUTFIT_GROUPS.map(g => g.name), ['', 'Seasonal', 'Everyday', 'Cat extras', "The cats' own"]);
  assert.deepEqual(Object.keys(core.OUTFIT_NAMES), core.OUTFIT_IDS);
  assert.ok(core.OUTFIT_IDS.every(id => /^[a-z]+$/.test(id)), 'lowercase letters only');
  assert.equal(core.DEFAULT_OUTFIT, 'auto');
  assert.deepEqual(core.OUTFIT_ROLES, ['big', 'small', 'kitten']);
});

test('a stored outfit: one of the 18 exactly as written, anything else is auto', () => {
  for (const id of core.OUTFIT_IDS) assert.equal(core.outfitIdOf(id), id);
  for (const v of ['Auto', 'BOW', ' bow', 'bow ', 'bow\n', '', 'fancyhat', 'hat', '__proto__', 'constructor', 'toString', null, undefined, 7, true, [], ['bow'], {}, { outfit: 'bow' }, NaN, () => 'bow'])
    assert.equal(core.outfitIdOf(v), 'auto', String(v));
  assert.deepEqual(core.cleanWardrobeSettings({ outfit: 'bow' }), { outfit: 'bow' });
  for (const v of [null, undefined, 'bow', 7, [], ['bow'], {}, { outfit: 7 }, { outfit: 'Bow' }, JSON.parse('{"__proto__":{"outfit":"bow"}}')]) assert.deepEqual(core.cleanWardrobeSettings(v), { outfit: 'auto' });
  assert.deepEqual(core.cleanWardrobeSettings({ character: 'momo', outfit: 'crown', desktop: { on: true } }), { outfit: 'crown' }, 'only its own key is read');
});

test('Easter: the known dates, the earliest and the latest, and the years it does not answer for', () => {
  const known = { 1818: [3, 22], 1943: [4, 25], 1961: [4, 2], 2000: [4, 23], 2008: [3, 23], 2016: [3, 27], 2024: [3, 31], 2025: [4, 20], 2026: [4, 5], 2038: [4, 25], 2285: [3, 22] };
  for (const [y, [month, day]] of Object.entries(known)) assert.deepEqual(core.easterOf(+y), { month, day }, y);
  for (const y of [1582, 0, -5, 10000, 2024.5, '2024', null, NaN, undefined]) assert.equal(core.easterOf(y), null, String(y));
  for (let y = 1583; y <= 2500; y++) { const e = core.easterOf(y), d = new Date(Date.UTC(y, e.month - 1, e.day)); assert.equal(d.getUTCDay(), 0, `${y} is a Sunday`); assert.ok(e.month === 3 ? e.day >= 22 : e.month === 4 && e.day <= 25, `${y}`); }
});

test('Auto: every boundary of the five rules, in their priority order', () => {
  const at = (y, m, d) => core.autoOutfitFor(y, m, d);
  const rules = [['partyhat', [[2025, 12, 31], [2026, 1, 1], [2026, 1, 2]], [[2025, 12, 30], [2026, 1, 3]]], ['santahat', [[2025, 12, 1], [2025, 12, 26]], [[2025, 11, 30], [2025, 12, 27]]],
    ['witchhat', [[2025, 10, 1], [2025, 10, 31], [2025, 11, 1]], [[2025, 9, 30], [2025, 11, 2]]], ['sunglasses', [[2025, 6, 21], [2025, 7, 15], [2025, 8, 31]], [[2025, 6, 20], [2025, 9, 1]]]];
  for (const [id, inside, outside] of rules) { for (const d of inside) assert.equal(at(...d), id, `${d} is ${id}`); for (const d of outside) assert.notEqual(at(...d), id, `${d} is not ${id}`); }
  assert.equal(at(2025, 3, 15), 'none'); assert.equal(at(2025, 5, 5), 'none');
  assert.equal(at(2024, 2, 29), 'none'); assert.equal(at(2024, 7, 4), 'sunglasses');
});

test('Auto: Good Friday to Easter Monday wears bunny ears, in every year, by the calendar and not by the day count', () => {
  const walk = (y, m, d, k) => { const t = new Date(Date.UTC(y, m - 1, d + k)); return [t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()]; };
  let seen = 0;
  for (let y = 1583; y <= 2600; y++) {
    const e = core.easterOf(y);
    for (let k = -4; k <= 3; k++) {
      const out = core.autoOutfitFor(...walk(y, e.month, e.day, k));
      assert.equal(out, k >= -2 && k <= 1 ? 'bunnyears' : 'none', `${y}: Easter ${k >= 0 ? '+' : ''}${k}`);
      if (out === 'bunnyears') seen++;
    }
  }
  assert.equal(seen, 4 * (2600 - 1583 + 1), 'four days a year, and the other four rules never touch them');
  assert.equal(core.autoOutfitFor(1500, 4, 1), 'none', 'a year before the Gregorian calendar has no Easter rule');
});

test('Auto: dates that are not dates, and the chosen value resolved for drawing', () => {
  for (const d of [[2023, 2, 29], [2024, 2, 30], [2024, 13, 1], [2024, 0, 1], [2024, 4, 31], [0, 1, 1], [10000, 1, 1], [2024.5, 1, 1], ['2024', 1, 1], [null, 1, 1], [2024, 1, 1.5]]) assert.equal(core.autoOutfitFor(...d), 'none', String(d));
  assert.equal(core.resolveOutfit('auto', 2025, 12, 24), 'santahat'); assert.equal(core.resolveOutfit('auto', 2025, 3, 3), 'none');
  assert.equal(core.resolveOutfit('none', 2025, 12, 24), 'none'); assert.equal(core.resolveOutfit('bow', 2025, 12, 24), 'bow');
  assert.equal(core.resolveOutfit('Bow', 2025, 12, 24), 'santahat', 'a value that is not an ID is auto');
  assert.equal(core.resolveOutfit(null, 2024, 3, 29), 'bunnyears');
  for (const id of core.OUTFIT_IDS) assert.notEqual(core.resolveOutfit(id, 2025, 7, 1), 'auto', 'never auto');
});

test('who wears it: the big-cat role at every size, never a kitten or a small cat', () => {
  assert.equal(core.outfitWorn('big'), true);
  for (const v of ['small', 'kitten', 'Big', ' big', '', null, undefined, 28, 20, 64, true, {}, []]) assert.equal(core.outfitWorn(v), false, String(v));
});

test('the fixture replays, part 1: the IDs, the clean-up, Easter, Auto and who wears it', () => {
  const f = fixture();
  assert.deepEqual(Object.keys(f).slice(0, 3), ['version', 'tolerance', 'note']);
  assert.deepEqual(compare(f.ids, core.OUTFIT_IDS), []); assert.deepEqual(compare(f.groups, core.OUTFIT_GROUPS), []); assert.deepEqual(compare(f.names, core.OUTFIT_NAMES), []);
  assert.equal(f.clean.length, 18 + 20); assert.equal(f.easterWindows.length, 12); assert.equal(f.worn.length, 16);
  for (const row of f.clean) assert.equal(core.outfitIdOf(row.input), row.out, row.name);
  for (const row of f.settings) assert.deepEqual(core.cleanWardrobeSettings(row.input), row.out, row.name);
  for (const row of f.easter) assert.deepEqual(core.easterOf(row.year), row.out, String(row.year));
  for (const row of f.auto) assert.equal(core.autoOutfitFor(row.y, row.m, row.d), row.out, `${row.y}-${row.m}-${row.d}`);
  for (const w of f.easterWindows) for (const d of w.days) assert.equal(core.autoOutfitFor(d.y, d.m, d.d), d.out, `${w.year} ${d.k}`);
  for (const row of f.resolve) assert.equal(core.resolveOutfit(row.id, row.y, row.m, row.d), row.out);
  for (const row of f.worn) assert.equal(core.outfitWorn(row.role), row.out, String(row.role));
});

test('the draw order: three slots that do not touch PASSES', () => {
  assert.deepEqual(core.OUTFIT_SLOTS, ['behind', 'neck', 'top']);
  assert.deepEqual(core.OUTFIT_ORDER.front, ['foldEars', 'collar', 'outfit.neck', 'outfit.top', 'whiskers', 'badge', 'particles', 'balls']);
  assert.deepEqual(core.OUTFIT_ORDER.behind, [...core.PASSES.behind, 'outfit.behind']);
  assert.equal(core.OUTFIT_ORDER.behind.indexOf('outfit.behind'), core.OUTFIT_ORDER.behind.indexOf('ears') + 1);
  assert.deepEqual(core.PASSES.front, ['foldEars', 'whiskers', 'badge', 'particles', 'balls'], 'PASSES stays as A-0 wrote it');
  assert.deepEqual(core.OUTFIT_MIN, { height: 6, line: 1, rim: 2, ball: 3, span: 6 });
});

test('the edge of a coat: light on a dark head, dark on a light one', () => {
  const light = core.CAT_IDS.filter(id => core.outfitEdge(core.PRESETS[id]) === 'light');
  assert.deepEqual(light, ['momo', 'midnight', 'oreo', 'mocha']);
  assert.equal(core.outfitEdge(core.PRESETS.ginger), 'dark'); assert.equal(core.outfitEdge(core.PRESETS.snow), 'dark');
});

test('anchors: the crown sits on the head between the ear bases, the chin runs left to right, on every coat at every size and turn', () => {
  for (const id of core.CAT_IDS) for (const D of [12, 18, 20, 28, 48, 64, 96]) for (const s of [REST, TURNED]) {
    const p = core.PRESETS[id], A = core.outfitAnchors(p, s, D, { dpr: 2 }), at = `${id} Ø${D}`;
    assert.ok(finite(A), at);
    assert.ok(A.top.y < -.6 * A.ry && A.top.y > -1.1 * A.ry, `${at}: the crown is at the top of the head`);
    assert.ok(A.gap > .3 * A.rx && A.gap < 1.2 * A.rx, `${at}: the ear bases are a head apart`);
    near(A.half * 2, A.gap, at);
    assert.equal(A.ears.length, 2); assert.deepEqual(A.ears.map(e => e.sd), [-1, 1]);
    assert.ok(A.ears[0].tipX < A.ears[0].bx && A.ears[1].tipX > A.ears[1].bx, `${at}: the ears lean outwards`);
    assert.ok(A.ears.every(e => e.tipY < e.by), `${at}: the tips are above the bases`);
    assert.equal(A.chin.pts.length, 26);
    assert.ok(A.chin.pts[0][0] < 0 && A.chin.pts[25][0] > 0, `${at}: the chin runs left to right`);
    assert.ok(A.chin.front[1] > .5 * A.ry && Math.abs(A.chin.front[0]) < .1 * A.rx + Math.abs(s.yaw) * A.rx, `${at}: the front of the chin`);
    assert.equal(A.edge, core.outfitEdge(p));
    assert.equal(A.eyes.length, 2);
  }
  const A2 = core.outfitAnchors(core.PRESETS.momo, REST, 64), A3 = core.outfitAnchors(core.PRESETS.momo, REST, 64, { dpr: 0 });
  assert.deepEqual(A2, A3, 'a dpr that is not above 0 is 2');
  assert.ok(Math.abs(core.outfitAnchors(core.PRESETS.momo, TURNED, 64).lean) > .05 && core.outfitAnchors(core.PRESETS.momo, REST, 64).lean === 0, 'a hat leans with the face turn');
});

test('the room above the crown: the distance to the strip, less the ear fit margin; none without a ceiling', () => {
  const A = { top: { x: 0, y: -8 } };
  near(core.outfitRoom(A, 16, 0), 7.5, 'the notch'); near(core.outfitRoom(A, 12, 0), 3.5, 'the strip without a notch'); assert.equal(core.outfitRoom(A, 4, 0), 0, 'no room is 0, never negative');
  for (const c of [null, undefined, 'x', NaN, Infinity]) assert.equal(core.outfitRoom(A, 16, c), null, String(c));
  for (const h of [null, undefined, 'x', NaN]) assert.equal(core.outfitRoom(A, h, 0), null, String(h));
});

test('the fixture replays, part 2: slots, floors, edges, rooms and anchors', () => {
  const f = fixture();
  assert.deepEqual(f.slots, core.OUTFIT_SLOTS); assert.deepEqual(f.order, core.OUTFIT_ORDER); assert.deepEqual(f.min, core.OUTFIT_MIN);
  assert.equal(Object.keys(f.anchors).length, 4 * 4 * 2);
  for (const [id, edge] of Object.entries(f.edge)) assert.equal(core.outfitEdge(core.PRESETS[id]), edge, id);
  for (const r of f.rooms) { const got = core.outfitRoom({ top: { x: 0, y: r.top } }, r.headY, r.ceiling); if (r.out === null || got === null) assert.equal(got, r.out, JSON.stringify(r)); else near(got, r.out, JSON.stringify(r)); }
  for (const [key, want] of Object.entries(f.anchors)) { const [cat, D, pose] = key.split('/'); assert.deepEqual(compare(core.outfitAnchors(core.PRESETS[cat], pose === 'rest' ? REST : TURNED, +D, { dpr: 2 }), want), [], key); }
});

const geo = (id, cat, D, s = REST, extra = {}) => {
  const p = core.PRESETS[cat], o = { dpr: 2, ...extra };
  if (D <= 20 && o.room === undefined) o.room = core.outfitRoom(core.outfitAnchors(p, s, D, o), (D === 20 ? 32 : 24) / 2, 0);
  return core.outfitGeometry(id, p, s, D, o);
};
const extent = (shapes, headY) => { // the highest and lowest point of a list of shapes in the strip, stroke widths included
  let hi = Infinity, lo = -Infinity;
  for (const sh of shapes) {
    const w = (sh.stroke ? sh.sw : 0) / 2;
    if (sh.k === 'ellipse') { const r = Math.hypot(sh.rx * Math.sin(sh.rot), sh.ry * Math.cos(sh.rot)); hi = Math.min(hi, headY + sh.y - r - w); lo = Math.max(lo, headY + sh.y + r + w); }
    else for (const q of sh.pts) { hi = Math.min(hi, headY + q[1] - w); lo = Math.max(lo, headY + q[1] + w); }
  }
  return { hi, lo };
};

test('what an outfit is made of: only the three kinds, real slots and roles, finite numbers, and nothing for the choices or a stranger', () => {
  const roles = new Set();
  const outfitRoles = new Set(['partyA', 'partyB', 'partyStar', 'santaRed', 'fur', 'witchHat', 'witchBand', 'gold', 'goldDark', 'bunnyOuter', 'bunnyInner', 'lens', 'frame', 'glint', 'beanieBody', 'beanieCuff', 'bowRed', 'bowKnot', 'scarfA', 'scarfB', 'rim', 'glassTint', 'gemA', 'gemB', 'gemC', 'silver', 'bandanaRed', 'white', 'fishBody', 'fishFin', 'petal', 'shrimp', 'shrimpDark', 'blossom', 'blossomDeep', 'leaf', 'edge']);
  const area = pts => Math.abs(pts.reduce((s, q, i) => { const r = pts[(i + 1) % pts.length]; return s + q[0] * r[1] - r[0] * q[1]; }, 0)) / 2; // shoelace
  for (const id of core.OUTFIT_DRAWN) for (const cat of core.CAT_IDS) for (const D of [18, 20, 28, 48, 64, 96]) for (const s of [REST, TURNED]) {
    const shapes = geo(id, cat, D, s), at = `${id} on ${cat} Ø${D}`;
    assert.ok(shapes.length > 0 && finite(shapes), at);
    for (const sh of shapes) {
      assert.ok(['poly', 'curve', 'ellipse'].includes(sh.k), at); assert.ok(core.OUTFIT_SLOTS.includes(sh.slot), at);
      for (const r of [sh.fill, sh.stroke]) if (r) roles.add(r);
      assert.ok(sh.a > 0 && sh.a <= 1 && sh.sw >= 0, at);
      if (sh.k === 'curve') assert.ok(sh.stroke && sh.sw > 0 && !('fill' in sh), `${at}: a curve is a stroke`);
      if (sh.k === 'ellipse') assert.ok(sh.rx > 0 && sh.ry > 0, at); else assert.ok(sh.pts.length >= 2 && sh.pts.every(q => q.length === 2), at);
      if (sh.k === 'poly') assert.ok(area(sh.pts) > 0, `${at}: a polygon with no area`);
      assert.equal(typeof sh.fine, 'boolean');
      if (sh.fine) assert.ok(D >= core.DETAIL_FULL_MIN, `${at}: a fine shape is left out below Ø28`);
    }
  }
  for (const r of roles) assert.ok(outfitRoles.has(r), `${r} is not one of the outfit roles`);
  for (const id of ['none', 'auto', 'fancyhat', '', null, 7, '__proto__', 'constructor']) assert.deepEqual(core.outfitGeometry(id, core.PRESETS.momo, REST, 64), [], String(id));
});

test('only the slots the design names: bunny ears behind, the neck three over the collar, the rest on top', () => {
  const slotsOf = id => [...new Set(geo(id, 'momo', 64).map(sh => sh.slot))];
  assert.deepEqual(slotsOf('bunnyears'), ['behind']);
  for (const id of ['scarf', 'bandana', 'bell']) assert.deepEqual(slotsOf(id), ['neck'], id);
  for (const id of ['partyhat', 'santahat', 'witchhat', 'sunglasses', 'beanie', 'bow', 'roundglasses', 'crown', 'fishclip', 'flower', 'shrimpclip', 'blossomclip']) assert.deepEqual(slotsOf(id), ['top'], id);
});

test('fit across 16 coats: hats stand between the ears, glasses sit on the eyes, clips and the bow at an ear base', () => {
  for (const cat of core.CAT_IDS) {
    const p = core.PRESETS[cat], A = core.outfitAnchors(p, REST, 64, { dpr: 2 }), x = shapes => shapes.flatMap(sh => sh.k === 'ellipse' ? [sh.x - sh.rx, sh.x + sh.rx] : sh.pts.map(q => q[0]));
    for (const id of ['partyhat', 'santahat', 'beanie', 'crown']) { const xs = x(geo(id, cat, 64)); assert.ok(Math.max(...xs) <= A.half * .97 && Math.min(...xs) >= -A.half * .97, `${cat} ${id}: narrower than the gap between the ear bases`); }
    { const xs = x(geo('witchhat', cat, 64)); assert.ok(Math.max(...xs) < A.half && Math.min(...xs) > -A.half, `${cat}: the witch brim is narrower than the ear spread`); }
    for (const id of ['sunglasses', 'roundglasses']) { const sh = geo(id, cat, 64).filter(q => q.k === 'ellipse'), e = A.eyes.filter(v => v.visible); for (const lens of sh.slice(0, 2)) assert.ok(e.some(v => Math.hypot(v.x - lens.x, v.y - lens.y) < 1e-9), `${cat} ${id}: a lens on an eye`); }
    for (const [id, sd] of [['bow', 1], ['flower', 1], ['blossomclip', 1], ['fishclip', -1], ['shrimpclip', -1]]) { const e = A.ears.find(v => v.sd === sd), d = geo(id, cat, 64).filter(q => q.k !== 'curve').map(q => q.k === 'ellipse' ? [q.x, q.y] : q.pts[0]).map(([a, b]) => Math.hypot(a - e.bx, b - e.by)); assert.ok(Math.min(...d) < .7 * A.R, `${cat} ${id}: at its ear base`); }
  }
});

test('the head turned: the glasses flatten with the eyes and a lens that turns out of sight is not drawn', () => {
  const lens = s => geo('sunglasses', 'momo', 64, s).filter(q => q.k === 'ellipse');
  assert.equal(lens(REST).length, 2); assert.ok(lens(TURNED).length >= 1);
  const big = lens(REST)[0].rx, narrow = lens({ ...REST, yaw: 1.2 }).map(l => l.rx);
  assert.ok(Math.min(...narrow) < big * .8, 'a turned lens is narrower');
  for (const id of core.OUTFIT_DRAWN) { const a = geo(id, 'momo', 64, REST), b = geo(id, 'momo', 64, TURNED); assert.notDeepEqual(a, b, `${id} follows the turn`); }
});

test('the collar: the bell hangs from each style, the neck outfits draw with the collar off, and nothing changes the collar', () => {
  const p = core.PRESETS.momo;
  for (const style of core.COLLAR_STYLES) {
    const before = JSON.stringify(core.collarGeometry(p, REST, 64, style, { dpr: 2 }));
    for (const id of ['bell', 'bandana', 'scarf']) { const s = core.outfitGeometry(id, p, REST, 64, { dpr: 2, collar: style }); assert.ok(s.length > 0, `${id} with ${style}`); assert.ok(s.every(q => q.slot === 'neck')); }
    assert.equal(JSON.stringify(core.collarGeometry(p, REST, 64, style, { dpr: 2 })), before, 'reading the collar never changes it');
  }
  const bellAt = style => { const s = core.outfitGeometry('bell', p, REST, 64, { dpr: 2, collar: style }), e = s.filter(q => q.k === 'ellipse'); return e.find(q => q.fill === 'gold'); };
  const tag = core.collarGeometry(p, REST, 64, 'tag', { dpr: 2 }), band = core.collarGeometry(p, REST, 64, 'band', { dpr: 2 }), ker = core.collarGeometry(p, REST, 64, 'kerchief', { dpr: 2 }), A = core.outfitAnchors(p, REST, 64, { dpr: 2 });
  assert.ok(bellAt('tag').y > tag.tag.y + tag.tag.r, 'below the tag'); near(bellAt('tag').x, tag.tag.x, 'tag');
  near(bellAt('band').x, band.band[band.band.length >> 1][0], 'band'); assert.ok(bellAt('band').y > band.band[band.band.length >> 1][1]);
  near(bellAt('kerchief').x, ker.kerchief.apex[0], 'kerchief'); assert.ok(bellAt('kerchief').y > ker.kerchief.apex[1] - 1e-9);
  near(bellAt('off').x, A.neck.x, 'off: its own ring at the front of the neck'); assert.ok(bellAt('off').y > A.neck.y);
  const sc = core.outfitGeometry('scarf', p, REST, 64, { dpr: 2 }), bd = core.outfitGeometry('bandana', p, REST, 64, { dpr: 2 });
  assert.ok(sc[0].sw > core.collarGeometry(p, REST, 64, 'band', { dpr: 2 }).width * 2, 'the scarf is wider than the band collar, so it covers it');
  const w = shapes => { const xs = shapes.flatMap(q => q.k === 'ellipse' ? [q.x] : q.pts.map(v => v[0])); return Math.max(...xs) - Math.min(...xs); };
  assert.ok(w(bd) > w([{ k: 'poly', pts: ker.kerchief.pts }]), 'the bandana is bigger than the kerchief collar');
});

test('fine details are left out below Ø28, and the rest stays', () => {
  const some = core.OUTFIT_DRAWN.filter(id => geo(id, 'momo', 28).length > geo(id, 'momo', 27).length);
  assert.ok(some.length >= 6, `${some}`);
  // The shrimp clip is simple below Ø28 (the owner's switch): its shapes are pinned by the switch test below, not by this count.
  for (const id of core.OUTFIT_DRAWN.filter(id => id !== 'shrimpclip')) { assert.ok(geo(id, 'momo', 27).length > 0, id); assert.ok(geo(id, 'momo', 28).filter(q => !q.fine).length === geo(id, 'momo', 27).length, `${id}: what is left is what is not fine`); }
});

test('the compact notch: every outfit on every coat reads at Ø20 and Ø18, stays inside the strip and never goes below its floors', () => {
  const dpr = 2, fl = n => core.OUTFIT_MIN[n] / dpr;
  for (const [H, D] of STRIPS) for (const cat of core.CAT_IDS) for (const id of core.OUTFIT_DRAWN) {
    const p = core.PRESETS[cat], A = core.outfitAnchors(p, REST, D, { dpr }), room = core.outfitRoom(A, H / 2, 0), shapes = geo(id, cat, D), at = `${id} on ${cat} Ø${D}`;
    assert.ok(room >= fl('height') - 1e-9, `${at}: the strip leaves ${room.toFixed(2)} pt, the floor is ${fl('height')}`);
    const { hi, lo } = extent(shapes, H / 2);
    assert.ok(hi >= -1e-9, `${at}: nothing above the strip (${hi.toFixed(2)})`); assert.ok(lo <= H + 1e-9, `${at}: nothing below the strip (${lo.toFixed(2)})`);
    for (const sh of shapes) { assert.ok(sh.k === 'ellipse' || sh.sw >= 0); if (sh.sw > 0) assert.ok(sh.sw >= fl('line') - 1e-9, `${at}: a stroke under the line floor`); if (sh.k === 'ellipse') assert.ok(Math.min(sh.rx, sh.ry) >= .5 * fl('ball') - 1e-9 || sh.fine, `${at}: an ellipse smaller than half a ball`); }
    const xs = shapes.flatMap(q => q.k === 'ellipse' ? [q.x - q.rx, q.x + q.rx] : q.pts.map(v => v[0])), ys = shapes.flatMap(q => q.k === 'ellipse' ? [q.y - q.ry, q.y + q.ry] : q.pts.map(v => v[1]));
    assert.ok(Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)) >= fl('span'), `${at}: at least a span across`);
  }
  // A hat is shortened to the room, and held at the floor when even that is short; no room means no limit.
  const p = core.PRESETS.momo, rise = (room, D = 20) => -Math.min(...core.outfitGeometry('partyhat', p, REST, D, { dpr, room }).filter(q => q.k === 'poly').flatMap(q => q.pts.map(v => v[1])));
  assert.ok(rise(3) < rise(100), 'a short room gives a shorter hat'); assert.ok(rise(0) > 0, 'and no room still draws one'); near(rise(0), rise(1), 'both are held at the floor');
  assert.ok(rise(100) > rise(3) + 1, 'a tall room gives the natural height');
  assert.deepEqual(core.outfitGeometry('partyhat', p, REST, 20, { dpr, room: null }), core.outfitGeometry('partyhat', p, REST, 20, { dpr }), 'no room is no limit');
});

test('the digest: counts, a box and the mean point; zeros for nothing', () => {
  assert.deepEqual(core.outfitDigest([]), { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 });
  assert.deepEqual(core.outfitDigest([{ k: 'poly', pts: [[0, 0], [2, 0], [2, 4]] }, { k: 'ellipse', x: 1, y: 1, rx: 3, ry: 1 }]), { n: 2, pts: 4, bbox: [-2, 0, 4, 4], mx: 1.25, my: 1.25 });
});

test('the fixture replays, part 3: shapes, digests, collars, fine details', () => {
  const f = fixture();
  assert.equal(Object.keys(f.digests).length, 16 * 16 * 4); assert.equal(Object.keys(f.geometry).length, 4); assert.deepEqual(f.strips, { 18: 24, 20: 32 });
  for (const [key, byOutfit] of Object.entries(f.geometry)) { const [cat, D, pose] = key.split('/'); for (const [id, want] of Object.entries(byOutfit)) assert.deepEqual(compare(geo(id, cat, +D, pose === 'rest' ? REST : TURNED), want), [], `${key} ${id}`); }
  for (const [key, want] of Object.entries(f.digests)) { const [cat, id, D] = key.split('/'); assert.deepEqual(compare(core.outfitDigest(geo(id, cat, +D)), want), [], key); }
  for (const [key, want] of Object.entries(f.collars)) { const [id, style] = key.split('/'); assert.deepEqual(compare(core.outfitGeometry(id, core.PRESETS.momo, REST, 64, { dpr: 2, collar: style }), want.shapes), [], key); assert.deepEqual(compare(core.collarGeometry(core.PRESETS.momo, REST, 64, style, { dpr: 2 }), want.collar), [], key); }
  for (const row of f.unknown) assert.deepEqual(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 64, { dpr: 2 }), row.out, String(row.id));
  for (const row of f.fine) { assert.equal(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 27, { dpr: 2 }).length, row.at27); assert.equal(core.outfitGeometry(row.id, core.PRESETS.momo, REST, 28, { dpr: 2 }).length, row.at28); }
});

test('the colours: every role the shapes use is a colour of the theme\'s outfits group, and every colour is used', () => {
  const PAL = JSON.parse(fs.readFileSync(new URL('../../shared/theme.json', import.meta.url), 'utf8')).outfits, roles = new Set();
  assert.ok(PAL && Object.keys(PAL).length > 20, 'the theme has an outfits group');
  for (const id of core.OUTFIT_DRAWN) for (const cat of core.CAT_IDS) for (const sh of geo(id, cat, 64)) for (const r of [sh.fill, sh.stroke]) if (r) roles.add(r);
  roles.delete('edge');
  assert.deepEqual([...roles].sort(), Object.keys(PAL).filter(k => k !== 'edgeLight' && k !== 'edgeDark').sort());
  assert.ok(['edgeLight', 'edgeDark'].every(k => k in PAL), 'the two edges are there');
  assert.ok(Object.values(PAL).every(v => /^#[0-9A-F]{6}$/.test(v)), 'every colour is #RRGGBB in capitals');
});

test('the prototype page: its copy of the palette is the theme\'s, it paints the three slots, and only the big cats wear the outfit', () => {
  const html = fs.readFileSync(new URL('../../design/prototype/notchmeow.html', import.meta.url), 'utf8'), theme = JSON.parse(fs.readFileSync(new URL('../../shared/theme.json', import.meta.url), 'utf8'));
  const m = /@@OUTFIT-PALETTE \*\/\s*const OW_PAL=(\{[^;]*\});\s*\/\* @@END-OUTFIT-PALETTE/.exec(html);
  assert.ok(m, 'the page has the marked palette');
  assert.deepEqual(JSON.parse(m[1]), theme.outfits);
  for (const slot of core.OUTFIT_SLOTS) assert.ok(html.includes(`owPaint(ctx,OWG,'${slot}')`), slot);
  assert.ok(html.includes('CatCore.outfitWorn(o.role)'), 'drawCat asks the contract who is dressed');
  assert.equal([...html.matchAll(/drawCat\([^\n]*?outfit:wdBig\(\),role:'big'/g)].length, 6, 'the six big-cat calls pass the role');
});

// ── The owner's checkpoint: the compact shrimp, the compact bunny ears, the dark-coat rim, the clip's name, the santa margin, the preview's headroom
const area = pts => Math.abs(pts.reduce((s, q, i) => { const r = pts[(i + 1) % pts.length]; return s + q[0] * r[1] - r[0] * q[1]; }, 0)) / 2; // shoelace, as above

test('the shrimp clip switches at the detail cut: a simple bold shrimp below Ø28, the detailed block from Ø28 on', () => {
  assert.equal(core.DETAIL_FULL_MIN, 28);
  for (const D of [18, 20, 27]) {
    const s = geo('shrimpclip', 'momo', D), at = `shrimp Ø${D}`;
    assert.deepEqual(s.map(q => q.k), ['curve', 'curve', 'poly'], `${at}: an edge round one thick curve, and one three-tip tail`);
    assert.equal(s[0].stroke, 'edge'); assert.equal(s[1].stroke, 'shrimp'); assert.ok(s[0].sw > s[1].sw && s[1].sw > 0, `${at}: the edge shows round the body`);
    assert.equal(s[2].fill, 'shrimp'); assert.equal(s[2].stroke, 'edge'); assert.equal(s[2].pts.length, 7, `${at}: three tips`);
    assert.ok(s.every(q => !q.fine), `${at}: nothing is fine at this size, it is all drawn`);
    assert.ok(area(s[2].pts) > 0, `${at}: the tail has area`);
  }
  for (const D of [28, 48, 64]) {
    const s = geo('shrimpclip', 'momo', D), body = s.filter(q => q.k === 'curve' && q.stroke === 'shrimp');
    assert.equal(body.length, 4, `Ø${D}: the four segments of the detailed body`);
    assert.ok(s.some(q => q.k === 'curve' && q.stroke === 'shrimpDark'), `Ø${D}: the joints`);
    assert.ok(!s.some(q => q.k === 'curve' && q.stroke === 'edge'), `Ø${D}: no simple edge curve`);
  }
});

test('the shrimp switch, pinned: the fixture rows record which shapes each side draws, at Ø18, Ø20, Ø27, Ø28 and Ø48', () => {
  const f = fixture();
  assert.equal(f.shrimpSwitch.threshold, core.DETAIL_FULL_MIN);
  assert.deepEqual(f.shrimpSwitch.rows.map(r => r.D), [18, 20, 27, 28, 48]);
  for (const row of f.shrimpSwitch.rows) {
    assert.equal(row.full, row.D >= core.DETAIL_FULL_MIN, `Ø${row.D}: the side`);
    const got = geo('shrimpclip', 'momo', row.D).map(sh => [sh.k, sh.slot, sh.fill ?? null, sh.stroke ?? null, sh.fine]);
    assert.deepEqual(got, row.shapes, `Ø${row.D}`);
  }
});

test('the bunny ears at compact sizes: taller above the crown, wider than the open ear fit, inside the strip, with pink insides', () => {
  for (const cat of ['momo', 'midnight']) for (const [H, D] of STRIPS) {
    const p = core.PRESETS[cat], A = core.outfitAnchors(p, REST, D, { dpr: 2 }), shapes = geo('bunnyears', cat, D), at = `${cat} bunny ears Ø${D}`;
    const outer = shapes.filter(q => q.fill === 'bunnyOuter'), inner = shapes.filter(q => q.fill === 'bunnyInner');
    assert.equal(outer.length, 2, at); assert.equal(inner.length, 2, `${at}: the pink insides`); assert.ok(inner.every(q => q.stroke === null), at);
    const tip = Math.min(...outer.flatMap(q => q.pts.map(v => H / 2 + v[1])));
    assert.ok(tip >= 0, `${at}: the room rule holds, the tips stay in the strip`);
    assert.ok(H / 2 + A.top.y - tip >= 3, `${at}: they stand at least 3 pt above the crown (${(H / 2 + A.top.y - tip).toFixed(2)})`);
    for (const q of outer) { const xs = q.pts.map(v => v[0]); assert.ok(Math.max(...xs) - Math.min(...xs) >= .9 * A.half, `${at}: each ear is about a head gap wide or more`); }
  }
});

test('the sunglasses on a dark head: a thin light rim in the edge role; a light head keeps the frame, as before', () => {
  const lenses = (cat, D = 64) => geo('sunglasses', cat, D).filter(q => q.k === 'ellipse' && q.fill === 'lens');
  assert.deepEqual(core.CAT_IDS.filter(c => core.outfitEdge(core.PRESETS[c]) === 'light'), ['momo', 'midnight', 'oreo', 'mocha']);
  for (const cat of core.CAT_IDS) {
    const edge = core.outfitEdge(core.PRESETS[cat]), R = core.outfitAnchors(core.PRESETS[cat], REST, 64, { dpr: 2 }).R, frame = Math.max(core.OUTFIT_MIN.rim / 2, .06 * R); // the frame width a light head keeps
    for (const lens of lenses(cat)) {
      if (edge === 'light') { assert.equal(lens.stroke, 'edge', `${cat}: the rim is the edge role`); assert.ok(lens.sw > 0 && lens.sw < frame, `${cat}: a thin rim (${lens.sw.toFixed(3)} against a frame of ${frame.toFixed(3)})`); }
      else { assert.equal(lens.stroke, 'frame', `${cat}: a light head keeps the frame`); near(lens.sw, frame, cat); }
    }
  }
  for (const row of fixture().lensRims) {
    assert.equal(row.lenses.length, 2, row.cat);
    assert.deepEqual(compare(lenses(row.cat).map(l => ({ stroke: l.stroke, sw: l.sw })), row.lenses), [], `${row.cat} lenses replay`);
  }
});

test('the clip is called Peach-blossom clip everywhere: the names, the fixture and the sheet label, which is not shortened', () => {
  assert.equal(core.OUTFIT_NAMES.blossomclip, 'Peach-blossom clip');
  assert.equal(fixture().names.blossomclip, 'Peach-blossom clip');
  const html = fs.readFileSync(new URL('../../design/prototype/notchmeow.html', import.meta.url), 'utf8');
  assert.ok(!/(^|[^-])Blossom clip/.test(html), 'the page does not say Blossom clip');
  assert.ok(!html.includes("replace('Peach-blossom','Blossom')"), 'the sheet label keeps the name');
});

test('the santa leaf keeps a clear margin inside the 24 pt strip at Ø18, on every coat: at least 0.3 pt, its area positive', () => {
  for (const cat of core.CAT_IDS) {
    const leaf = geo('santahat', cat, 18).find(q => q.k === 'poly' && q.fill === 'santaRed' && q.stroke === null), at = `${cat} santa leaf Ø18`;
    assert.ok(leaf, at);
    const top = Math.min(...leaf.pts.map(v => 12 + v[1]));
    assert.ok(top >= .3, `${at}: the margin is ${top.toFixed(3)} pt`);
    assert.ok(area(leaf.pts) > 0, `${at}: the leaf has area`);
  }
});

test('the Wardrobe preview has headroom for a Ø170 witch hat: its tip is inside the canvas on momo, with a margin', () => {
  const html = fs.readFileSync(new URL('../../design/prototype/notchmeow.html', import.meta.url), 'utf8');
  const m = /const WD_PREVIEW_TOP=(\d+);/.exec(html);
  assert.ok(m, 'the page has the headroom constant'); const TOP = +m[1];
  assert.ok(html.includes("W=820,H=270+WD_PREVIEW_TOP;") && html.includes('ctx.translate(0,WD_PREVIEW_TOP)'), 'the canvas is grown by the headroom and drawn below it');
  assert.ok(html.includes('owCat(ctx,c,id,130,150,170)'), 'the Ø170 cat is drawn with its head at y 150');
  const hat = core.outfitGeometry('witchhat', core.PRESETS.momo, REST, 170, { dpr: 2 });
  const tip = Math.min(...hat.flatMap(q => q.k === 'ellipse' ? [q.y - q.ry] : q.pts.map(v => v[1])));
  const MARGIN = 16;
  assert.ok(150 + TOP + tip >= MARGIN, `the tip sits at ${(150 + TOP + tip).toFixed(1)} px from the canvas top, the margin is ${MARGIN}`);
});
