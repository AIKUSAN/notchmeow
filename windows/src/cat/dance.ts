// The music bob (spec §3, "Music"): the cat hops and sways to the beat while music plays, with its ears bouncing as it lands. The numbers are the Mac's
// (CatEffects.applyDance and CatEngine's dancing level: 112 BPM, a hop of 0.20 R, a sway of 0.08 R, a roll of 0.10 rad, a landing squash, a fade in
// over 0.3 s and out over 0.5 s). The ear bounce is this app's own: the Mac's bob moves the head and the ears ride with it. Pure, so the plain-Node
// checks (npm run check:cat) can load it. Nothing on Windows or Linux says "music is playing" yet: `State.musicPlaying` is the seam.

/** The tempo of the dance. */
export const DANCE_BPM = 112;

const beatOf = (seconds: number) => (seconds * DANCE_BPM) / 60;
/** 1 as the head lands, 0 in the air: the landing squash and the ears follow it. */
const landing = (beat: number) => Math.pow(1 - Math.abs(Math.sin(Math.PI * beat)), 6);

export interface DancePose { dx: number; dy: number; rot: number; sx: number; sy: number }

/** Where the head is on the beat: moved by (dx, dy) px, rolled by `rot` rad, squashed by (sx, sy). `level` (0 to 1) is how much it dances, R the head radius in px. */
export function dancePose(level: number, seconds: number, R: number): DancePose {
  const beat = beatOf(seconds), s = Math.sin(Math.PI * beat), hop = Math.abs(s), land = landing(beat);
  return { dx: 0.08 * R * s * level, dy: -0.2 * R * hop * level, rot: 0.1 * s * level, sx: 1 + 0.045 * land * level, sy: 1 - 0.06 * land * level };
}

/** The part of a canvas context the bob needs. */
export interface DanceCtx { translate(x: number, y: number): void; rotate(a: number): void; scale(x: number, y: number): void }

/** Applies the bob to the context around the bottom of the head (px, py) before the cat is drawn. Does nothing at level 0 or for a bad number. */
export function applyDance(c: DanceCtx, level: number, seconds: number, px: number, py: number, R: number): void {
  if (!(level > 0.001)) return;
  const p = dancePose(level, seconds, R);
  c.translate(px + p.dx, py + p.dy);
  c.rotate(p.rot);
  c.scale(p.sx, p.sy);
  c.translate(-px, -py);
}

/** The dancing level one frame later: it rises over 0.3 s while music plays and falls over 0.5 s after. A bad frame time changes nothing. */
export function danceLevel(level: number, on: boolean, dt: number): number {
  if (!(dt >= 0) || !Number.isFinite(dt)) return level;
  return on ? Math.min(1, level + dt / 0.3) : Math.max(0, level - dt / 0.5);
}

/** How much higher the ears stand than at rest (a delta on the `earU` target): they spring up as the head lands and settle as it rises. */
export const danceEars = (level: number, seconds: number): number => 0.14 * level * landing(beatOf(seconds));

/** The states in which the Mac's cat dances: not asleep, not asking, not hurt. */
const DANCE_STATES: ReadonlySet<string> = new Set(["idle", "working", "thinking", "searching", "finished"]);

/** Whether the cat bobs now: music plays, the island is compact (the Mac's expanded case is the music pill's card, which this app does not have), and the cat is in a calm state. */
export const shouldDance = (playing: boolean, state: string, mode: string): boolean => playing && mode === "compact" && DANCE_STATES.has(state);
