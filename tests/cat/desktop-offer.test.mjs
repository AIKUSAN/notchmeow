import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

// The incoming transfer offer (G2-0): a card from another machine is an alert to the desktop cat, like an approval. One flag, no new phase, event or act.
// docs/CAT-CONTRACT.md, "The transfer offer".
const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));

test('desktopAlert: transferOffer counts only when it is exactly true', () => {
  const a = core.desktopAlert;
  assert.equal(a({ transferOffer: true }), true);
  assert.equal(a({ transferOffer: true, fileCatch: true }), true);
  for (const v of [false, 'true', 1, null, [true], {}, undefined]) assert.equal(a({ transferOffer: v }), false, JSON.stringify(v));
  for (const k of ['offer', 'transfer', 'transfer_offer', 'TransferOffer', 'transferOffers']) assert.equal(a({ [k]: true }), false, k);
});

test('the other alerts still count, and input that is not an object is still no alert', () => {
  const a = core.desktopAlert;
  for (const k of ['approval', 'question', 'chatApproval', 'fileCatch']) assert.equal(a({ [k]: true }), true, k);
  assert.equal(a({ pillStates: ['approval'] }), true);
  for (const v of [null, undefined, 'transferOffer', 1, true, [true]]) assert.equal(a(v), false, String(v));
});

test('a transfer offer adds no phase, event or act, and the older alert rows stand untouched', () => {
  assert.equal(core.DESKTOP_PHASES.length, 7);
  assert.equal(core.DESKTOP_EVENTS.length, 9);
  assert.equal(core.DESKTOP_ACTS.length, 11);
  assert.ok(fx.alertCases.length >= 23, 'alertCases keeps its rows');
  assert.ok(fx.alertCases.every(c => !JSON.stringify(c.input).includes('transferOffer')), 'no transferOffer in alertCases: apps that replay it today stay green');
});

test('offerCases replay, and each row that carries the flag as exactly true is an alert', () => {
  assert.ok(fx.offerCases.length >= 13);
  for (const c of fx.offerCases) assert.equal(core.desktopAlert(c.input), c.out, c.name);
  assert.ok(fx.offerCases.some(c => c.input.transferOffer === true && c.out === true));
  for (const c of fx.offerCases) if (c.input.transferOffer !== true && !['approval', 'question', 'chatApproval', 'fileCatch'].some(k => c.input[k] === true)) assert.equal(c.out, false, c.name);
});

test('the three "a transfer offer" trips are in trips, after the file catch ones', () => {
  const names = fx.trips.map(t => t.name);
  const first = names.findIndex(n => n.startsWith('a transfer offer'));
  assert.ok(first > names.findIndex(n => n.startsWith('a file catch')));
  assert.equal(names.filter(n => n.startsWith('a transfer offer')).length, 3);
});
