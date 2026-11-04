// A frame loop that runs only while its page can be seen. The Settings window is created hidden at launch and kept for the whole run, so a
// loop that ran all the time would cost CPU with Settings closed. `sync()` is the only control: call it on load and whenever the page may
// have been shown or hidden (visibilitychange, focus, blur). Plain data in, no DOM, so the plain-Node checks (npm run check:cat) can drive it.

export interface LoopEnv {
  /** requestAnimationFrame. */
  raf(cb: (ms: number) => void): number;
  /** cancelAnimationFrame. */
  caf(id: number): void;
  /** Whether anyone can see the page right now. */
  visible(): boolean;
}

export class VisibleLoop {
  private id: number | null = null;
  private last = -1;
  private readonly frame: (dt: number) => void;
  private readonly env: LoopEnv;

  /** `frame` gets the seconds since the last frame: 0 on the first, never negative, never more than 0.05. */
  constructor(frame: (dt: number) => void, env: LoopEnv) {
    this.frame = frame;
    this.env = env;
  }

  /** True while a frame is scheduled. */
  get running(): boolean { return this.id !== null; }

  /** Starts the loop if the page can be seen and it is stopped; stops it if the page cannot be seen. */
  sync(): void {
    if (!this.env.visible()) {
      if (this.id !== null) { this.env.caf(this.id); this.id = null; }
      return;
    }
    if (this.id !== null) return;
    this.last = -1;
    this.id = this.env.raf(this.tick);
  }

  private tick = (ms: number) => {
    this.id = null;
    if (!this.env.visible()) return;
    const dt = this.last < 0 ? 0 : Math.min(0.05, Math.max(0, (ms - this.last) / 1000));
    this.last = Number.isFinite(ms) ? ms : this.last;
    this.frame(Number.isFinite(dt) ? dt : 0);
    this.id = this.env.raf(this.tick);
  };
}
