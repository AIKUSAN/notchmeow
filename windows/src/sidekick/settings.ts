// The Sidekick settings as the app edits them (sub-project F1, spec "Settings" and "Dismissal memory"): the master switch, the local-voice switch and the dismissal
// counts of the five kinds of note. Every change goes through the contract's clean-up (`cleanSidekickSettings`), so a value that is not one of the allowed ones never
// gets stored. Pure: the Settings window and the island both call these, and the plain-Node checks load this file.

import { DISMISS_KINDS, cleanSidekickSettings, dismiss, mute, muted, unmute } from "./core.ts";
import type { NoteKind, SidekickSettings } from "./core.ts";

/** The words Settings → Sidekick uses for each kind of note (the spec's "Muted notes" rows). */
export const KIND_LABELS: Record<NoteKind, string> = {
  recap: "Away recaps",
  "stuck.loop": "Repeated steps",
  "stuck.errors": "Repeated errors",
  "stuck.waiting": "Waiting for your OK",
  "stuck.silent": "Gone quiet",
};

/** What a fresh install holds: everything on, nothing dismissed. */
export const defaultSidekick = (): SidekickSettings => cleanSidekickSettings(null);

/** "Recaps and nudges": off means no recap and no stuck nudge. The permission line has no switch. */
export const withSidekickOn = (s: SidekickSettings, on: boolean): SidekickSettings => cleanSidekickSettings({ ...s, on });

/** "Nicer wording from a local model": off means only the plain templates. */
export const withLocal = (s: SidekickSettings, local: boolean): SidekickSettings => cleanSidekickSettings({ ...s, local });

/** One more dismissal of a kind (a click on Not now, OK or ×). Two mute it. */
export const withDismissed = (s: SidekickSettings, kind: NoteKind): SidekickSettings => cleanSidekickSettings({ ...s, dismissals: dismiss(s.dismissals, kind) });

/** Mute a kind at once (the Settings tab's own rows, with no dismissal in between): that kind goes to 2, the mute. */
export const withMuted = (s: SidekickSettings, kind: NoteKind): SidekickSettings => cleanSidekickSettings({ ...s, dismissals: mute(s.dismissals, kind) });

/** Unmute in Settings: that kind goes back to 0. */
export const withUnmuted = (s: SidekickSettings, kind: NoteKind): SidekickSettings => cleanSidekickSettings({ ...s, dismissals: unmute(s.dismissals, kind) });

/** The kinds that are muted now, in the contract's order: the rows under "Muted notes". */
export const mutedKinds = (s: SidekickSettings): NoteKind[] => DISMISS_KINDS.filter((k) => muted(s.dismissals, k));
