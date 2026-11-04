// Playful motion: cat body language on top of the same engine (hops, ear flicks, bleps, hisses, zoomies).
// A port of PLAYFUL in design/prototype/cat-core.js, the tie-breaker.
// Imports only types from the engine, so there is no import cycle at run time.

import { TAU, zoomiesOnFinish } from "../base.ts";
import type { StateName } from "../base.ts";
import type { BotEngine, MotionProfile } from "../engine.ts";
import type { EyeShape, Targets } from "../types.ts";

/** Eye, tilt, earL, earR, earU, earF, pupil, oy: the pose of each state at rest. */
const REST: Record<StateName, readonly [EyeShape, number, number, number, number, number, number, number]> = {
  idle: ["pill", 0, 0, 0, 1, 0, 0.45, 0],
  working: ["pill", 0, -0.08, -0.08, 1.1, 0, 0.5, 0],
  thinking: ["pill", 0.14, 0, 0.38, 1, 0, 0.55, 0],
  searching: ["wide", 0, -0.1, -0.1, 1.15, 0, 0.92, 0.05],
  approval: ["wide", 0, -0.12, -0.12, 1.22, 0, 0.75, 0],
  question: ["pill", 0.24, -0.05, 0.5, 1, 0, 0.7, 0],
  error: ["flat", 0, 0, 0, 1, 1, 0.12, 0],
  finished: ["happy", 0, 0.12, 0.12, 1, 0, 0.45, 0],
  ratelimit: ["tired", 0, 0, 0, 0.9, 0.45, 0.4, 0],
  sleeping: ["closed", 0, 0, 0, 1, 0.25, 0.45, 0.08],
  dizzy: ["spiral", 0, 0, 0, 1, 0, 0.45, 0],
};

export const PLAYFUL: MotionProfile = {
  key: "playful",
  label: "Playful",
  eye: (st) => REST[st][0],
  enter(c: BotEngine, st: StateName, prev: StateName) {
    const a = c.anim.bind(c);
    if (prev === "sleeping" && st !== "sleeping" && st !== "dizzy") c.later(220, () => c.zoomies(), "st");
    switch (st) {
      case "idle": if (prev !== "idle") c.blink(); break;
      case "working": c.blink(); c.twitch("earL"); c.later(140, () => c.twitch("earR"), "st"); break;
      case "thinking": c.blink(); break;
      case "searching": a("oy", [[0.12, 160, "out"], [0.05, 300, "inOut"]]); break;
      case "approval":
        a("oy", [[0.08, 110, "out"], [-0.26, 170, "out"], [0, 340, "back"]]);
        a("sy", [[0.88, 110, "out"], [1.1, 170, "out"], [1, 340, "back"]]);
        a("sx", [[1.08, 110, "out"], [0.94, 170, "out"], [1, 340, "back"]]);
        a("earU", [[1.4, 140, "out"], [1.22, 300, "inOut"]]);
        break;
      case "question": a("tilt", [[0.3, 220, "out"], [0.24, 300, "inOut"]]); c.blink(); break;
      case "error":
        a("sx", [[1.14, 80, "out"], [1, 450, "inOut"]]); a("sy", [[1.1, 80, "out"], [1, 450, "inOut"]]); a("oy", [[0.07, 80, "out"], [0, 420, "inOut"]]);
        a("earF", [[1, 90, "out"]]); a("wh", [[0.35, 80, "out"], [0, 500, "inOut"]]);
        c.mpose({ mouth: 0.75, smile: -1, mround: 0 }, 650, 80, 220);
        c.later(900, () => c.hairball(), "st");
        break;
      case "finished":
        if (zoomiesOnFinish(c.workedFor, c.cfg.zoomAfter)) { c.later(150, () => c.zoomies(), "st"); c.later(2200, () => c.emit("spark", 4), "st"); break; }
        a("tilt", [[0.16, 260, "inOut"], [-0.16, 420, "inOut"], [0.08, 320, "inOut"], [0, 300, "inOut"]]);
        a("blush", [[0.8, 250, "out"], [0.8, 900, "lin"], [0, 500, "inOut"]]);
        c.later(350, () => c.emit("spark", 5), "st");
        break;
      case "ratelimit": c.nextYawn = c.now() + 300; break;
    }
  },
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number] {
    const r = REST[st];
    tg.tilt = r[1]; tg.earL = r[2]; tg.earR = r[3]; tg.earU = r[4]; tg.earF = r[5]; tg.pupil = r[6]; tg.oy = r[7];
    let ty = c.lookX * 0.62, tp = c.lookY * 0.5;
    if (st === "thinking") { ty = ty * 0.35 - 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5; }
    if (st === "sleeping") { ty = 0; tp = -0.14; tg.sy = 1 + 0.04 * Math.sin(1.2 * T); tg.sx = 1 - 0.04 * 0.57 * Math.sin(1.2 * T); }
    if (st === "searching") { ty = Math.sin(2.2 * T) * 0.55; tg.earL = -0.1 - Math.sin(2.2 * T) * 0.28; tg.earR = -0.1 + Math.sin(2.2 * T) * 0.28; }
    if (st === "dizzy") { ty = Math.sin(3.5 * T) * 0.2; tg.tilt = Math.sin(7 * T) * 0.12; tg.earL = Math.sin(9 * T) * 0.45; tg.earR = -Math.sin(9 * T + 1) * 0.45; }
    if (st === "approval") tg.oy = -Math.pow(Math.max(0, Math.sin((TAU * T) / 1.4)), 4) * 0.09;
    if (st === "working") tg.oy = -Math.pow(Math.abs(Math.sin(Math.PI * 1.6 * T)), 2) * 0.035;
    return [ty, tp];
  },
  post(c: BotEngine, st: StateName, T: number, kG: number) {
    const s = c.s;
    if (!c.tw.ox) {
      if (st === "searching") s.ox = Math.sin(16 * T) * 0.012;
      else if (st === "dizzy") s.ox = Math.cos(7 * T) * 0.07;
      else s.ox += (0 - s.ox) * kG;
    }
    if (st === "dizzy" && !c.tw.oy) s.oy = Math.sin(7 * T) * 0.05;
  },
  ambient(c: BotEngine, t: number) {
    const st = c.state;
    if (st === "idle" && t >= c.nextBlep) {
      if (!c.tw.tongue && !c.tw.mouth) { if (c.rand() < 0.55) c.blep(); else c.lick(); }
      c.nextBlep = t + c.u(8000, 15000);
    }
    if (["idle", "working", "thinking", "sleeping", "finished", "question"].includes(st) && t >= c.nextTw) {
      c.twitch(c.rand() < 0.5 ? "earL" : "earR");
      c.nextTw = t + (st === "working" ? c.u(1500, 3000) : st === "sleeping" ? c.u(4000, 8000) : c.u(3000, 7000)) * c.pm().earFlickEvery;
    }
    if (st === "idle" && t >= c.nextSB) { c.slowBlink(); c.nextSB = t + c.u(8000, 14000) * c.pm().slowBlinkEvery; }
    if (st === "ratelimit" && t >= c.nextYawn) { PLAYFUL.emote(c, "yawn"); c.nextYawn = t + 4800; }
    if (st === "sleeping" && t >= c.nextAmb) { c.emit("z", 1); c.nextAmb = t + 1600; }
  },
  squash: [0.86, 1.1],
  emote(c: BotEngine, n: string) {
    const a = c.anim.bind(c), d = 1800;
    switch (n) {
      case "love":
        c.ov("closed", d); a("purr", [[1, 200, "out"], [1, d - 500, "lin"], [0, 300, "inOut"]]); a("blush", [[1, 300, "out"], [1, d - 600, "lin"], [0, 300, "inOut"]]);
        a("earL", [[0.18, 250, "out"], [0.18, d - 500, "lin"], [0, 250, "inOut"]]); a("earR", [[0.18, 250, "out"], [0.18, d - 500, "lin"], [0, 250, "inOut"]]);
        a("tilt", [[c.lookX >= 0 ? 0.12 : -0.12, 400, "inOut"], [0, 900, "inOut"]]); c.emit("heart", 3);
        break;
      case "surprised":
        c.ov("dot", 1100); a("earU", [[1.38, 90, "out"], [1, 600, "inOut"]]); a("sx", [[1.12, 80, "out"], [1, 500, "inOut"]]); a("sy", [[1.12, 80, "out"], [1, 500, "inOut"]]);
        a("oy", [[-0.2, 120, "out"], [0, 400, "back"]]); a("pupil", [[1, 100, "out"], [1, 700, "lin"], [0.45, 400, "inOut"]]); a("wh", [[0.4, 80, "out"], [0, 500, "inOut"]]);
        break;
      case "proud":
        c.ov("happy", d); a("lift", [[0.28, 260, "out"], [0.28, d - 560, "lin"], [0, 300, "inOut"]]); a("earU", [[1.15, 200, "out"], [1.15, d - 500, "lin"], [1, 300, "inOut"]]);
        c.emit("spark", 4); a("blush", [[0.5, 250, "out"], [0.5, d - 550, "lin"], [0, 300, "inOut"]]);
        break;
      case "wink": c.ov("wink", 1100); c.twitch("earR"); a("tilt", [[0.1, 180, "out"], [0.1, 700, "lin"], [0, 240, "inOut"]]); break;
      case "yawn":
        c.ov("closed", 1300); a("mouth", [[1, 450, "out"], [1, 500, "lin"], [0, 350, "inOut"]]); a("sy", [[1.12, 450, "inOut"], [1, 800, "inOut"]]);
        a("sx", [[0.94, 450, "inOut"], [1, 800, "inOut"]]); a("earF", [[0.75, 450, "inOut"], [c.tg.earF, 800, "inOut"]]);
        break;
      case "happy":
        c.ov("happy", 1400); a("oy", [[-0.06, 120, "out"], [0, 160, "inOut"], [-0.06, 120, "out"], [0, 200, "back"]]); a("earU", [[1.12, 150, "out"], [1, 600, "inOut"]]);
        a("blush", [[0.6, 200, "out"], [0, 700, "inOut"]]);
        break;
      case "annoyed": c.ov("line", 900); a("earF", [[1, 60, "out"], [1, 700, "lin"], [c.tg.earF, 400, "inOut"]]); a("wh", [[0.4, 60, "out"], [0, 400, "inOut"]]); break;
    }
  },
};
