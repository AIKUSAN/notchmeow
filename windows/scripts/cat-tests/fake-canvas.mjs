// A canvas that draws nothing and checks what it is asked to draw: every number is finite, so a NaN
// that would blank a cat in a browser fails here instead. Enough of the 2D API for the cat renderer.
import assert from "node:assert/strict";

/** Counts of the calls made, by name (`ctx.calls`), and what the checks look at (`ctx.seen`): every string a `fillStyle` was set to, the arguments of every `ellipse`, and the colour of every gradient stop. */
export function fakeCanvas() {
  const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [], stops: [], texts: [] };
  const note = (name, args) => {
    calls[name] = (calls[name] || 0) + 1;
    for (const a of args) if (typeof a === "number") assert.ok(Number.isFinite(a), `${name}(${args.join(", ")}) was given ${a}`);
  };
  const store = {};
  const gradient = { addColorStop: (...a) => { seen.stops.push(a[1]); note("addColorStop", a.slice(0, 1)); } };
  const ctx = new Proxy(store, {
    get(t, k) {
      if (k === "calls") return calls;
      if (k === "seen") return seen;
      if (k in t) return t[k];
      if (k === "createLinearGradient" || k === "createRadialGradient") return (...a) => { note(k, a); return gradient; };
      if (k === "isPointInPath") return () => false;
      if (k === "measureText") return () => ({ width: 10 });
      return (...a) => { if (k === "ellipse") seen.ellipses.push(a); if (k === "fillText") seen.texts.push(a[0]); return note(String(k), a); };
    },
    set(t, k, v) {
      if (typeof v === "number") assert.ok(Number.isFinite(v), `${String(k)} = ${v}`);
      if (k === "fillStyle" && typeof v === "string") seen.fillStyles.push(v);
      if (k === "strokeStyle" && typeof v === "string") seen.strokeStyles.push(v);
      if (k === "lineWidth" && typeof v === "number") seen.lineWidths.push(v);
      t[k] = v;
      return true;
    },
  });
  return ctx;
}

/** A fakeCanvas that also records where every path point lands in the canvas (`ctx.points`, [x, y] after the current transform), so a test can ask what is drawn above the top (y < 0). Ellipses and arcs are sampled. */
export function pointCanvas() {
  const base = fakeCanvas(), pts = [], stack = [];
  let m = [1, 0, 0, 1, 0, 0];
  const mul = (a, b) => [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3], a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5]];
  const put = (x, y) => pts.push([m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]);
  const ring = (x, y, rx, ry, rot, a0, a1) => { for (let i = 0; i <= 64; i++) { const t = a0 + ((a1 - a0) * i) / 64, u = rx * Math.cos(t), v = ry * Math.sin(t); put(x + u * Math.cos(rot) - v * Math.sin(rot), y + u * Math.sin(rot) + v * Math.cos(rot)); } };
  const ops = {
    save() { stack.push(m); return base.save(); },
    restore() { if (stack.length) m = stack.pop(); return base.restore(); },
    translate(x, y) { m = mul(m, [1, 0, 0, 1, x, y]); return base.translate(x, y); },
    rotate(a) { m = mul(m, [Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), 0, 0]); return base.rotate(a); },
    scale(x, y) { m = mul(m, [x, 0, 0, y, 0, 0]); return base.scale(x, y); },
    setTransform(...a) { m = a.length === 6 ? a : [1, 0, 0, 1, 0, 0]; return base.setTransform(...a); },
    moveTo(x, y) { put(x, y); return base.moveTo(x, y); },
    lineTo(x, y) { put(x, y); return base.lineTo(x, y); },
    quadraticCurveTo(...a) { for (let i = 0; i < 4; i += 2) put(a[i], a[i + 1]); return base.quadraticCurveTo(...a); },
    bezierCurveTo(...a) { for (let i = 0; i < 6; i += 2) put(a[i], a[i + 1]); return base.bezierCurveTo(...a); },
    ellipse(x, y, rx, ry, rot, a0 = 0, a1 = 2 * Math.PI) { ring(x, y, rx, ry, rot, a0, a1); return base.ellipse(x, y, rx, ry, rot, a0, a1); },
    arc(x, y, r, a0, a1) { ring(x, y, r, r, 0, a0, a1); return base.arc(x, y, r, a0, a1); },
  };
  const c = new Proxy(base, { get: (t, k) => (k in ops ? ops[k] : base[k]), set: (t, k, v) => { base[k] = v; return true; } });
  c.points = pts;
  return c;
}

/** The two browser globals the renderer touches: Path2D, and document.createElement("canvas") for fur lines. */
export function installBrowserStubs() {
  globalThis.Path2D = class {
    constructor() { return new Proxy(this, { get: (t, k) => (k in t ? t[k] : () => {}) }); }
  };
  globalThis.document = { createElement: () => ({ getContext: () => fakeCanvas() }) };
}
