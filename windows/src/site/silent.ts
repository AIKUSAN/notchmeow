// The site makes no sound and ships no audio code: vite.site.config.ts swaps core/sound.ts for this, which has the one call the engine makes.
export const Sound = { play(_name: string): void {} };
