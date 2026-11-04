// The words and the switches the Settings pages show beside a pill, a key or a service: the four-slot cap, the chips and the dot each chip gets. Port of
// NotchBuddy/Sources/App/SettingsStatus.swift (one table, so every chip of the same word has the same dot). A missing prerequisite never disables a switch; only the cap does.
// Pure: no DOM. Tests: windows/scripts/settings-tests (check:settings); drift.test.mjs holds the words to the Swift file.

export interface Slots { text: string; names: string[]; full: boolean }
export interface PillSwitch { showsSwitch: boolean; chip: string | null; disabled: boolean }
export type Tone = "ok" | "warn" | "neutral" | "error";
/** What the credential store says about a key: stored, not stored, or a store that cannot be read (never taken for not stored). */
export type Presence = "present" | "absent" | "unreadable";
/** The chip of a key the store could not be read for. */
export const UNREADABLE_CHIP = "Couldn't read";
/** The Your AI row's chip for the same. */
export const UNREADABLE_ROW_CHIP = "Couldn't read the credential store";

export const MAX_SLOTS = 4;
export const CAP_SENTENCE = "4 of 4 slots used. Turn another off.";

/** The words each dot is given by, and the prefixes that count too. */
export const TONE_WORDS: Record<"ok" | "warn" | "error", readonly string[]> = {
  ok: ["Ready", "Installed", "Saved", "Main"],
  warn: ["Needs update", "Not saved", "Hooks not installed", "Key not configured", "Not connected", "Update needed", CAP_SENTENCE],
  error: ["Not ready"],
};
export const TONE_PREFIXES: Record<"ok" | "warn", string> = { ok: "Running", warn: "Off" };

/** The slot count, and the names of the active ids in catalog order (an id the catalog does not hold is counted but not named). */
export function slots(active: readonly string[], catalog: readonly { id: string; name: string }[]): Slots {
  const on = new Set(active);
  return {
    text: `${on.size} of ${MAX_SLOTS} slots used`,
    names: catalog.filter((c) => on.has(c.id)).map((c) => c.name),
    full: on.size >= MAX_SLOTS,
  };
}

/** The main pill has no switch and says "Main". An off pill at the cap is disabled with the cap sentence; otherwise the chip is the missing prerequisite, if any, and never disables. */
export function pillSwitch(isOn: boolean, isMain: boolean, activeCount: number, missing: string | null): PillSwitch {
  if (isMain) return { showsSwitch: false, chip: "Main", disabled: false };
  if (!isOn && activeCount >= MAX_SLOTS) return { showsSwitch: true, chip: CAP_SENTENCE, disabled: true };
  return { showsSwitch: true, chip: missing, disabled: false };
}

/** The pill list after one switch, or null when nothing changes: a pill is added only under the four-slot cap (a stale list of five or more never grows), and a switch
 * that already says so changes nothing. Removing a pill is always allowed. */
export function nextActive(active: readonly string[], id: string, on: boolean): string[] | null {
  if (on) {
    if (active.includes(id) || active.length >= MAX_SLOTS) return null;
    return [...active, id];
  }
  if (!active.includes(id)) return null;
  return active.filter((x) => x !== id);
}

/** "Needs update" wins; null when the hooks' state is not known. */
export function hookChip(installed: boolean | null, needsUpdate: boolean): string | null {
  if (needsUpdate) return "Needs update";
  if (installed == null) return null;
  return installed ? "Installed" : "Not installed";
}

export function keyChip(saved: boolean): string { return saved ? "Ready" : "No key yet"; }

/** The words a hook card says when settings.json is there but cannot be used (the Rust status's `error`, the same sentence). */
export const UNREADABLE_SETTINGS = "Couldn't read settings.json.";

/** The words an agent's card says when its config file is there but cannot be used (the Rust status's `error` for Gemini and Antigravity). */
export const UNREADABLE_CONFIG = "Couldn't read the config file.";

/** The part of a hook status the card reads: whether the hooks are in, and the read error when settings.json cannot be used. */
export interface HookStatusLike { installed: boolean; error?: string | null }

/** What each fixed `reason` of the Rust status says about the file, and what to do. Never the file's text or its path: only these words reach the card. */
const UNUSABLE: Record<string, readonly [why: string, remedy: string]> = {
  "unreadable": ["It couldn't be opened.", "Check that nothing else has it open and that you may read it, then Check again."],
  "not valid JSON": ["It isn't valid JSON.", "Fix or move the file, then Check again."],
  "not an object": ["It isn't a JSON object.", "Fix or move the file, then Check again."],
  "unexpected hooks shape": ["Its \"hooks\" section isn't in a shape NotchMeow can add to.", "Fix or move the file, then Check again."],
};

/** The card's line for a file that cannot be used: the fixed sentence for its kind, then why and what to do (a reason this build does not know adds only the generic remedy). */
export function unusableHelp(claude: boolean, reason: string | null | undefined): string {
  const [why, remedy] = reason != null && Object.hasOwn(UNUSABLE, reason) ? UNUSABLE[reason]! : ["", "Fix or move the file, then Check again."];
  return [claude ? UNREADABLE_SETTINGS : UNREADABLE_CONFIG, why, remedy].filter(Boolean).join(" ");
}

/** A hook card's chip: "Couldn't read" when the read failed or settings.json cannot be used; otherwise the hooks' chip, and "Checking…" until a read lands. */
export function hookCardChip(status: HookStatusLike | null, failed: boolean): string {
  if (status?.error || (!status && failed)) return UNREADABLE_CHIP;
  return hookChip(status?.installed ?? null, false) ?? "Checking…";
}

/** What a failed credential write or removal ends with, on the Keys tab and on the Services cards alike. The store's own text is never shown. */
export const CREDENTIAL_SAVE_FAILED = "Couldn't save to the credential store.";
export const CREDENTIAL_REMOVE_FAILED = "Couldn't remove it from the credential store.";

/** The note after a Claude Code write: where the previous settings were kept, or that there was no file to keep (the write made it). */
export function claudeBackupNote(saved: string, show: (path: string) => string): string {
  return saved ? `Previous settings saved as ${show(saved)}.` : "The file didn't exist, so it was created.";
}

/** A key's chip from the three-way presence: an unreadable store says so; present and absent are keyChip's. */
export function presenceChip(p: Presence): string { return p === "unreadable" ? UNREADABLE_CHIP : keyChip(p === "present"); }

export function serviceChip(saved: boolean): string { return saved ? "Saved" : "No key yet"; }

/** The notice a Services card's save ends with: the usual sentence, or the readable ones when an unreadable typed field stayed unsaved. */
export function savedNote(unreadableStayed: boolean): string {
  return unreadableStayed ? "Saved the readable ones." : "Saved. It never touches disk.";
}

/** The dot a chip gets: green for the ready words, amber for what needs the user, red for "Not ready", grey for the rest. */
export function tone(chip: string): Tone {
  // The two unreadable-store words are Windows and Linux only (the Mac has no such state), so they are not in TONE_WORDS, which drift.test.mjs holds to the Mac.
  if (chip === UNREADABLE_CHIP || chip === UNREADABLE_ROW_CHIP) return "warn";
  if (TONE_WORDS.ok.includes(chip) || chip.startsWith(TONE_PREFIXES.ok)) return "ok";
  if (TONE_WORDS.warn.includes(chip) || chip.startsWith(TONE_PREFIXES.warn)) return "warn";
  if (TONE_WORDS.error.includes(chip)) return "error";
  return "neutral";
}
