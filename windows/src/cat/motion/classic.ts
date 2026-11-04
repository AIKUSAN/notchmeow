// Classic motion: upstream's timings 1:1, with the cat's face on the same body language.
// A port of CLASSIC in design/prototype/cat-core.js, the tie-breaker.
// Imports only types from the engine, so there is no import cycle at run time.

import { TAU } from "../base.ts";
import type { StateName } from "../base.ts";
import type { BotEngine, MotionProfile } from "../engine.ts";
import type { EyeShape, Targets } from "../types.ts";

/** Eye shape and head tilt of each state at rest. */
const REST: Record<StateName, readonly [EyeShape, number]> = {
  idle: ["pill", 0], working: ["pill", 0], thinking: ["pill", 0], searching: ["pill", 0], approval: ["wide", 0],
  question: ["pill", 0.17], error: ["flat", 0], finished: ["happy", 0], ratelimit: ["tired", 0], sleeping: ["closed", 0], dizzy: ["spiral", 0],
};

export const CLASSIC: MotionProfile = {
  key: "classic",
  label: "Classic",
  eye: (st) => REST[st][0],
  enter(c: BotEngine, st: StateName, prev: StateName) {
    const a = c.anim.bind(c);
    switch (st) {
      case "idle": if (prev !== "idle") c.blink(); break;
      case "approval": a("oy", [[-0.2, 150, "out"], [0, 300, "back"]]); break;
      case "error": a("ox", [[0.08, 50, "out"], [-0.08, 70, "inOut"], [0.05, 70, "inOut"], [0, 90, "out"]]); break;
      case "finished": a("roll", [[TAU, 950, "inOut"]], () => { c.s.roll = 0; }); c.later(500, () => c.emit("spark", 5), "st"); break;
      case "ratelimit": c.emit("sweat", 1); break;
      case "dizzy": a("roll", [[2 * TAU, 1300, "inOut"]], () => { c.s.roll = 0; }); break;
      default: c.blink();
    }
  },
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number] {
    tg.tilt = REST[st][1]; tg.earL = 0; tg.earR = 0; tg.earU = 1; tg.earF = 0; tg.pupil = 0.45; tg.oy = 0;
    let ty = c.lookX * 0.62, tp = c.lookY * 0.5;
    if (st === "thinking") { ty = ty * 0.35 + 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5; }
    if (st === "sleeping") { ty = 0; tp = -0.14; tg.sy = 1 + 0.035 * Math.sin(1.8 * T); tg.sx = 1 - 0.035 * 0.57 * Math.sin(1.8 * T); }
    if (st === "searching") { ty = Math.sin(2.6 * T) * 0.6; tp = -0.06; }
    if (st === "dizzy") ty = Math.sin(9 * T) * 0.25;
    if (st === "approval") tg.oy = -Math.abs(Math.sin(5.2 * T)) * 0.07;
    return [ty, tp];
  },
  post(c: BotEngine, _st: StateName, _T: number, kG: number) {
    if (!c.tw.ox) c.s.ox += (0 - c.s.ox) * kG;
  },
  ambient(c: BotEngine, t: number) {
    if (t < c.nextAmb) return;
    if (c.state === "sleeping") c.emit("z", 1);
    if (c.state === "ratelimit" && !c.isMini && c.rand() < 0.5) c.emit("sweat", 1);
    c.nextAmb = t + 1300;
  },
  squash: [0.78, 1.16],
  emote(c: BotEngine, n: string) {
    const a = c.anim.bind(c), d = 1800;
    switch (n) {
      case "love": c.ov("heart", d); a("blush", [[1, 300, "out"], [1, d - 600, "lin"], [0, 300, "inOut"]]); c.emit("heart", 4); a("oy", [[-0.1, 160, "out"], [0, 300, "back"]]); break;
      case "surprised": c.ov("dot", d); a("oy", [[-0.3, 140, "out"], [0, 380, "back"]]); a("es", [[1.25, 120, "out"], [1, 500, "inOut"]]); break;
      case "proud": c.ov("star", d); c.emit("star", 5); a("tilt", [[-0.14, 220, "out"], [-0.14, d - 500, "lin"], [0, 280, "inOut"]]); a("blush", [[0.7, 250, "out"], [0.7, d - 550, "lin"], [0, 300, "inOut"]]); break;
      case "wink": c.ov("wink", d); a("tilt", [[0.12, 160, "out"], [0.12, d - 400, "lin"], [0, 240, "inOut"]]); break;
      case "yawn":
        c.ov("tired", d); a("sy", [[1.12, 500, "inOut"], [1, 500, "inOut"]]); a("sx", [[0.94, 500, "inOut"], [1, 500, "inOut"]]); a("mouth", [[0.8, 500, "inOut"], [0, 500, "inOut"]]);
        c.later(700, () => { c.ov("closed", 1100); c.emit("z", 2); });
        break;
      case "happy": c.ov("happy", d); a("blush", [[0.6, 200, "out"], [0, 600, "inOut"]]); break;
      case "annoyed": c.ov("line", 800); break;
    }
  },
};
