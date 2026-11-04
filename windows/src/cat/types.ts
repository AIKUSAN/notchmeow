// The cat's shared types. Nothing here exists at run time.
// Units are R, the head radius, unless a name says px or ms.

import type { MouthKey } from "./base.ts";

/** Every animatable property of the pose, as in cat-core.js `newPose()`. */
export type PoseKey =
  | "yaw" | "pitch" | "roll" | "tilt" | "open" | "sx" | "sy" | "oy" | "ox" | "tint" | "blush" | "es"
  | "badgeS" | "earL" | "earR" | "earU" | "earF" | "pupil" | "mouth" | "purr" | "lid" | "lift" | "wh"
  | "paws" | "smile" | "tongue" | "mround" | "mskew" | "wavy";
export type Pose = Record<PoseKey, number>;

/** The targets the pose eases toward each frame. */
export type TargetKey =
  | "yaw" | "pitch" | "tilt" | "sx" | "sy" | "es" | "oy" | "earL" | "earR" | "earU" | "earF" | "pupil"
  | "purr" | "lid" | MouthKey;
export type Targets = Record<TargetKey, number>;

export type Coat = "tuxedo" | "tabby" | "solid" | "point" | "calico";

export interface EarSpec { h: number; bw: number; rot: number; tip: number; tuft: number; cx?: number; fold?: number }
export interface EyeSpec { th: number; ph: number; w: number; h: number; round: number }
export interface WhiskSpec {
  rows: number; cols: number; x0: number; dx: number; y0: number; dy: number; slope: number; dot: number;
  wcols: number[]; a0: number; da: number; len: number; dl: number; droop: number; w: number; alpha: number; brow: number;
}
export interface RuffSpec { rx: number; ry: number; dy: number; col: [string, string] }
export interface FurOpts { n: number; l0: number; l1: number; w: number; dark: string; light: string; wDark?: string; wLight?: string }
/** A calico patch: x, y, a, b, rotation, colour, seed. */
export type Patch = [number, number, number, number, number, string, number];

/** One cat, fully resolved. The ids are frozen contract values. */
export interface CatPreset {
  name: string; label: string; desc?: string; voice: number; coat: Coat;
  rx: number; ry: number; n: number; fluff: number; ruff: RuffSpec | null; bib?: string;
  furOpts?: FurOpts; earSpread: number; ear: EarSpec;
  top: string; bot: string; rimLight?: number; white?: string; inner: string;
  light?: string; chinCol?: string; stripe?: string; point?: string; earCols?: [string, string];
  muzzle?: string; patches?: Patch[]; hairless?: number; wrinkles?: number;
  nose: string; noseLine: string; noseW: number; noseH: number; nosePh: number;
  iris: [string, string]; irisR?: [string, string]; lidTint?: string; liner: string; ink: string;
  mouthLine: string; whisk: string; padDot: string; whisk2: WhiskSpec; eye: EyeSpec;
  pupil0: number; blushAt: [number, number]; paw: string; bean: string;
  hair: string; hairDark: string; hairLight: string;
  kitten?: boolean; base?: string;
}

/** What a personality is as a cat stores it: the preset name and the six traits. */
export interface Traits { energy: number; curiosity: number; chatty: number; affection: number; sass: number; mischief: number }
export type Persona = Traits & { preset: string };

export type EyeShape =
  | "pill" | "wide" | "dot" | "line" | "flat" | "happy" | "closed"
  | "spiral" | "heart" | "star" | "tired" | "wink";

export type ParticleKind = "heart" | "star" | "spark" | "sweat" | "dust" | "hair" | "z";
/** A little thing that floats up and fades: hearts, stars, sparks, sweat, dust, hair, z. Positions are in R from the cat. */
export interface Particle { k: ParticleKind; x: number; y: number; vx: number; vy: number; age: number; life: number; size: number; rot: number }

/** A hairball, or a refused file wrapped in fur, bouncing and rolling away. Positions are in R from the cat. */
export interface Ball { x: number; y: number; vx: number; vy: number; rot: number; age: number; life: number; file: string | null; seed: number; floor: number }
