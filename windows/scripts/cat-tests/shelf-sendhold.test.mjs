import test from "node:test";
import assert from "node:assert/strict";

// The send's hold (island/sendhold.ts): the island stays held while a Share window is up and for 15 s after it ran, and a second send replaces the first send's timer
// (the Mac re-arms on each picker reading). The window's timers are turned by hand here, in seconds.

let clock = 0;
let nextId = 1;
const timers = new Map();
globalThis.window = {
  setTimeout: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: clock + ms / 1000 }); return id; },
  clearTimeout: (id) => { timers.delete(id); },
};
function advance(s) {
  const end = clock + s;
  for (;;) {
    const due = [...timers.entries()].filter(([, x]) => x.at <= end + 1e-9).sort((a, b) => a[1].at - b[1].at)[0];
    if (!due) break;
    clock = Math.max(clock, due[1].at);
    timers.delete(due[0]);
    due[1].fn();
  }
  clock = end;
}
const { SendHold } = await import("../../src/island/sendhold.ts");

function make() {
  timers.clear();
  clock = 0;
  const hold = { held: false };
  const sends = new SendHold((on) => { hold.held = on; }, 15_000);
  return { sends, hold };
}

test("a send holds the island while it runs, and for 15 s after its share ran", () => {
  const { sends, hold } = make();
  sends.start();
  assert.equal(hold.held, true);
  sends.finish();
  advance(14.9);
  assert.equal(hold.held, true, "14.9 s after the share ran: still held");
  advance(0.1);
  assert.equal(hold.held, false, "15 s after: released, and no timer is left");
  assert.equal(timers.size, 0);
});

test("two sends 10 s apart keep the island held until 15 s after the second", () => {
  const { sends, hold } = make();
  sends.start();
  sends.finish();          // the first share ran at 0 s: its timer would release at 15 s
  advance(10);
  sends.start();           // the second send at 10 s replaces that timer
  assert.equal(hold.held, true);
  sends.finish();          // the second share ran at 10 s
  advance(5);              // 15 s: the first send's timer would have released here
  assert.equal(hold.held, true, "15 s: still held by the second send");
  advance(9.5);            // 24.5 s
  assert.equal(hold.held, true, "24.5 s: still held");
  advance(0.5);            // 25 s: 15 s after the second share ran
  assert.equal(hold.held, false, "25 s: released, 15 s after the second send");
  assert.equal(timers.size, 0, "one timer at a time, and none left");
});

test("a second send that starts before the first share ran keeps the island held through its own 15 s", () => {
  const { sends, hold } = make();
  sends.start();
  advance(3);
  sends.start();           // the second send, while the first Share window is still up
  sends.finish();          // the first share runs out at 3 s
  advance(20);
  assert.equal(hold.held, false, "the last share ended at 3 s: released at 18 s, 15 s after");
});
