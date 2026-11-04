// The desktop cat's frame-rate governor (sub-project H, spec §3). `desktopFps` (desktop.ts, the contract) says how many frames a second the cat needs; this keeps to it. At 60 it
// follows the display's own frame callback; at any lower rate it sleeps on one timer between frames, so a cat that is idle wakes the page five times a second and a cat that cannot be
// seen (0) wakes it never: no timer, no frame callback. Pure: the clock, the timers and the frame callback are injected, so the plain-Node checks (npm run check:cat) turn time by hand.

export interface GovEnv {
  now(): number;
  raf(cb: () => void): number;
  caf(id: number): void;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

/** A frame may be this many seconds after the last, however long the wait was (a cat asleep draws every 2 s): the engine holds it to 0.25 anyway. */
export const MAX_DT = 0.25;

export class FrameGovernor {
  private rate = 0;
  private raf: number | null = null;
  private timer: number | null = null;
  private last = -1;
  private readonly env: GovEnv;
  private readonly draw: (dt: number) => void;

  /** `draw` gets the seconds since the last frame: 0 on the first after a start, never more than MAX_DT. */
  constructor(env: GovEnv, draw: (dt: number) => void) {
    this.env = env;
    this.draw = draw;
  }

  /** Frames a second now: 0 stops everything; a rate that is not a finite number is 0. A new rate takes effect at once, and the same rate leaves the schedule alone. */
  setRate(fps: number): void {
    const next = typeof fps === "number" && Number.isFinite(fps) && fps > 0 ? Math.min(60, fps) : 0;
    if (next === this.rate) return;
    this.rate = next;
    this.stop();
    if (next === 0) { this.last = -1; return; }
    this.schedule();
  }

  /** Draws one frame now, whatever the rate (an emote started, a message arrived) and carries on at the rate. */
  poke(): void {
    if (this.rate === 0) return;
    this.stop();
    this.frame();
  }

  get fps(): number { return this.rate; }
  get running(): boolean { return this.raf !== null || this.timer !== null; }

  private stop(): void {
    if (this.raf !== null) { this.env.caf(this.raf); this.raf = null; }
    if (this.timer !== null) { this.env.clear(this.timer); this.timer = null; }
  }

  private schedule(): void {
    if (this.rate >= 60) this.raf = this.env.raf(() => { this.raf = null; this.frame(); });
    else this.timer = this.env.set(() => { this.timer = null; this.frame(); }, 1000 / this.rate);
  }

  private frame(): void {
    const now = this.env.now(), dt = this.last < 0 ? 0 : Math.min(MAX_DT, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    this.draw(Number.isFinite(dt) ? dt : 0);
    if (this.rate > 0 && !this.running) this.schedule();
  }
}
