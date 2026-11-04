// What the Settings window shows when its settings file could not be used at boot (Task 3 of the Windows and Linux Settings polish). Pure: app.ts draws the banner through
// shell.ts's pinned strip. The problem is Rust's `SettingsProblem`; the buttons each case offers are here so they are tested. Outside Tauri there is no file to refuse,
// so a missing boot is no problem there. Tests: scripts/settings-tests/boot.test.mjs (check:settings).
import type { BootInfo, SettingsProblem } from "../core/bridge.ts";
import { DEFAULT_SETTINGS, type Settings } from "../core/state.ts";

/** The banner's problem: Rust's, or `failed` when the boot command itself failed inside Tauri (Rust's state is not known). */
export type BootBanner = SettingsProblem | { kind: "failed" };

export interface BootState {
  /** The settings the window starts with: the defaults, or the ones Rust sent. */
  settings: Settings;
  /** The banner's problem; null when there is none. */
  banner: BootBanner | null;
  /** The banner's buttons, in order. Empty with no banner. */
  buttons: readonly string[];
}

/** `inTauri` is bridge.ts's IS_TAURI. A boot the command failed on (`undefined`) inside Tauri is an unknown file: the defaults, and only Try again (Start fresh is
 * offered once Rust has seen the file unreadable). Outside Tauri it is no problem at all, as before. */
export function bootState(boot: BootInfo | undefined, inTauri: boolean): BootState {
  const settings: Settings = { ...DEFAULT_SETTINGS, ...boot?.settings };
  if (boot === undefined) {
    return inTauri
      ? { settings, banner: { kind: "failed" }, buttons: ["Try again"] }
      : { settings, banner: null, buttons: [] };
  }
  const banner = bannerOf(boot.settingsProblem);
  return { settings, banner, buttons: buttonsFor(banner) };
}

function bannerOf(problem: SettingsProblem | null | undefined): BootBanner | null {
  if (!problem) return null;
  if (problem.kind === "unreadable") return { kind: "unreadable" };
  const name = problem.keptAs ? fileName(problem.keptAs) : "";
  return name ? { kind: "unparseable", keptAs: name } : { kind: "unparseable" };
}

/** Unreadable: Try again, and Start fresh (it accepts the defaults if the file still cannot be read). Unparseable: Dismiss only. The copy already exists, and a retry
 * would read the same broken file again. */
function buttonsFor(banner: BootBanner | null): string[] {
  if (!banner) return [];
  if (banner.kind === "failed") return ["Try again"];
  return banner.kind === "unreadable" ? ["Try again", "Start fresh"] : ["Dismiss"];
}

/** The last part of a path, whichever separator it uses: the page never shows a folder. */
export function fileName(path: string): string {
  return path.split(/[\\/]/).pop() ?? "";
}

export function bannerText(b: BootBanner): string {
  if (b.kind === "failed") return "Your settings couldn't be loaded, so you are seeing defaults. Nothing is saved until Try again works.";
  if (b.kind === "unreadable") {
    return "Your settings couldn't be read, so you are seeing defaults. Nothing is saved until you choose. Start fresh replaces it with your next change.";
  }
  return b.keptAs
    ? `Your settings file couldn't be read. It was kept as ${b.keptAs}; you are seeing defaults.`
    : "Your settings file couldn't be read. A copy was kept; you are seeing defaults.";
}
