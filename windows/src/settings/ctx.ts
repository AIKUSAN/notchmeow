// What every Settings page is built from (Settings restyle, Task 5): the backend, the settings the window holds, the typed drafts, how to open a place, and the platform.
// Task 9 adds the AI cache as `ai`. The page contract (PageView) is the one a shell mounts and disposes.
import type { Settings } from "../core/state.ts";
import type { SettingsBackend } from "./backend.ts";
import type { DraftBook } from "./drafts.ts";
import type { Platform } from "./devices.ts";
import type { Place } from "./route.ts";
import type { AiCache } from "./aicache.ts";
import type { LiveProject } from "../projects/present.ts";

export interface SettingsCtx {
  backend: SettingsBackend;
  settings(): Settings;
  /** Applies the change, then asks the store; resolves true when the store confirmed it, false when it refused (the window has gone back to the stored value by then). */
  save(next: Settings): Promise<boolean>;
  home: string;
  drafts: DraftBook;
  open(place: Place): void;
  platform: Platform;
  desktopNote: string | null;
  ai: AiCache;
  /** The live projects' folder names, as the island last sent them (Settings → Cat → Project cats). */
  projects: () => readonly LiveProject[];
}

export interface PageView { el: HTMLElement; sync?(): void; dispose?(): void }
