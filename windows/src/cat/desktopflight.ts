// The desktop cat's flight in the air (sub-project H, spec §1): one clock for a trip between the notch spot and the desktop spot. The path is `desktopFlightAt`; this keeps the
// time. A flight that turns around (an alert that clears, a send-home during a flight) keeps its clock and carries on from progress 1 - t over the same path the other way. Pure:
// the time is given, never read.

import { DESKTOP_FLIGHT_MS, desktopFlightAt, spotOf } from "./desktop.ts";
import type { Spot } from "./desktop.ts";

export class DesktopFlight {
  private from: Spot;
  private to: Spot;
  private t0: number;
  private p0 = 0;
  /** Which end is the notch spot now: the flight starts at it (`out`) or ends at it (`in`). */
  private notchIs: "from" | "to";
  private readonly ms: number;

  /** A flight from `from` to `to` that begins at `now` (ms). `dir` 'out' means `from` is the notch spot, 'in' that `to` is. */
  constructor(from: Spot, to: Spot, now: number, dir: "out" | "in", ms = DESKTOP_FLIGHT_MS) {
    this.from = spotOf(from) ?? { x: 0, y: 0 };
    this.to = spotOf(to) ?? { x: 0, y: 0 };
    this.t0 = Number.isFinite(now) ? now : 0;
    this.notchIs = dir === "out" ? "from" : "to";
    this.ms = Number.isFinite(ms) && ms > 0 ? ms : DESKTOP_FLIGHT_MS;
  }

  /** How far along it is, 0 to 1. */
  progress(now: number): number {
    const t = this.p0 + (Number.isFinite(now) ? (now - this.t0) / this.ms : 0);
    return t < 0 ? 0 : t > 1 ? 1 : t;
  }

  /** The cat's spot and whether the flight is over. */
  at(now: number): { x: number; y: number; done: boolean } {
    const p = desktopFlightAt(this.from, this.to, this.progress(now));
    return { x: p.x, y: p.y, done: this.progress(now) >= 1 };
  }

  /** Reverses the flight: carries on from progress 1 - t, towards the end it came from. */
  turn(now: number): void {
    const t = this.progress(now);
    [this.from, this.to] = [this.to, this.from];
    this.notchIs = this.notchIs === "from" ? "to" : "from";
    this.p0 = 1 - t;
    this.t0 = Number.isFinite(now) ? now : this.t0;
  }

  /** The notch spot moved (the island opened for an alert, or shut): the notch end follows it. */
  setNotch(spot: Spot): void {
    const s = spotOf(spot);
    if (!s) return;
    if (this.notchIs === "from") this.from = s; else this.to = s;
  }

  /** The desktop spot moved (the screens changed): the desktop end follows it. */
  setDesktop(spot: Spot): void {
    const s = spotOf(spot);
    if (!s) return;
    if (this.notchIs === "from") this.to = s; else this.from = s;
  }

  get direction(): "out" | "in" { return this.notchIs === "from" ? "out" : "in"; }
}
