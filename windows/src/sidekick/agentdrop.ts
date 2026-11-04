// Dropping a file on an agent's own cat (sub-project F1, spec "Drop on an agent's cat"): the pure rules. The agent that cat stands for gets a path, not the file: the path goes to the
// clipboard, the agent's terminal or editor is brought forward where the system lets it, and the island says honestly what happened. Nothing is pasted, typed or sent to another program,
// no session is touched and the line never says "sent" or "delivered". The big drop area is never a target: a drop on it is the chat or Ask drop it always was. Pure; loaded by the plain-Node checks.

import { isAgentPill } from "../cat/display.ts";
import { agentName } from "./core.ts";

export interface Rect { x: number; y: number; w: number; h: number }

/** An agent's cat in the drop strip: whose it is, and where it is on the page (CSS px, the page's own coordinates). */
export interface DropTarget { agentId: string; rect: Rect }

/** The part of the cast a chip's coat is read from (cat/cast.ts). */
export interface CastView {
  big: { pill: string | null; cat: string };
  pills: readonly { pill: string; cat: string }[];
  second: { pill: string | null; cat: string } | null;
}

/** An agent a file can be dropped on, with the coat its chip wears. */
export interface DropAgent { agentId: string; cat: string }

/** At most this many chips: the island's pill row holds four. */
export const MAX_CHIPS = 4;

/**
 * The chips shown while a file is dragged over the island: **one for each running agent** (Claude Code, Gemini CLI, Antigravity, any other tagged agent), in the island's order, in every
 * display mode. "Running" is a live session in the ledger; an agent is a pill that is Claude Code or an `agent_<tag>`, never an integration. The chip wears the agent's coat where the cast gives
 * it one (the big cat's, a pill's, cat 2's), else the big cat's. The chips are an additive strip over the drop view: the big drop area is not one of them and does not move.
 */
export function dropAgents(tasks: readonly { id: string }[], cast: CastView, live: readonly string[]): DropAgent[] {
  const coat = new Map<string, string>();
  for (const p of cast.pills) coat.set(p.pill, p.cat);
  if (cast.big.pill) coat.set(cast.big.pill, cast.big.cat);
  if (cast.second?.pill) coat.set(cast.second.pill, cast.second.cat);
  return tasks
    .filter((t) => isAgentPill(t.id) && live.includes(t.id))
    .slice(0, MAX_CHIPS)
    .map((t) => ({ agentId: t.id, cat: coat.get(t.id) ?? cast.big.cat }));
}

/** How far outside a cat's rectangle a drop still counts (px): an aim that is a little off is still the cat's. */
export const DROP_SLACK = 4;

/** The agent whose cat is under the point, or null. The first target in the list wins where two overlap. */
export function agentCatAt(x: number, y: number, targets: readonly DropTarget[]): string | null {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  for (const t of targets) {
    const r = t.rect;
    if (x >= r.x - DROP_SLACK && x <= r.x + r.w + DROP_SLACK && y >= r.y - DROP_SLACK && y <= r.y + r.h + DROP_SLACK) return t.agentId;
  }
  return null;
}

/**
 * Where a drop happened, in the page's CSS pixels: Tauri gives the position in physical pixels, so it is divided by the device pixel ratio. Where the system gives none (or a number that is
 * not one) the last cursor position the page knows is used.
 */
export function dropPoint(position: { x: number; y: number } | undefined, dpr: number, fallback: { x: number; y: number }): { x: number; y: number } {
  if (position && Number.isFinite(position.x) && Number.isFinite(position.y) && Number.isFinite(dpr) && dpr > 0) return { x: position.x / dpr, y: position.y / dpr };
  return fallback;
}

// The Mac's rule (NotchBuddy/Sources/App/SidekickDrop.swift, commit 66c4804), by Unicode property and not by a list of ranges. A scalar no path may hold: a control (Cc), a format character (Cf:
// bidi controls, zero-width, joiners), a line or paragraph separator (Zl, Zp), any default-ignorable code point (invisible: it shows a name other than the one a shell reads), a lone surrogate
// (Cs: it cannot cross to the clipboard intact), a backslash and a `!` (fish reads a backslash inside single quotes, csh and tcsh expand a `!` even there: no quoting is enough for them).
const REFUSED = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Cs}\p{Default_Ignorable_Code_Point}\\!]/u;
// Windows: the same refusals without the backslash, which every drive-letter and UNC path holds, and the `!` refused too (bash, zsh and Git Bash history expansion can run earlier commands). Every Windows
// path is wrapped in double quotes, and inside those PowerShell and cmd still expand `$`, a backtick and `%`: refused. A straight `"` and the quote-like U+201C, U+201D, U+201E, U+201F, U+FF02 are refused
// too: they end our quoting. A Unicode space other than U+0020 (NBSP, en space, ideographic space) is refused too: it looks like a space and is not one to a prompt. `(?!\x20)\p{Zs}` is a Zs character that is not U+0020.
const REFUSED_WINDOWS = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Cs}\p{Default_Ignorable_Code_Point}$`%!"“”„‟＂]|(?!\x20)\p{Zs}/u;
// A path a POSIX shell reads as itself: it starts with `/` and holds only ASCII letters and digits, `_ . / + @ % , : = -`, or a non-ASCII letter, mark or number.
const PLAIN = /^\/[\p{L}\p{M}\p{N}_./+@%,:=-]*$/u;

/** One path as the clipboard gets it: as it is when plain, else in POSIX single quotes (sh, bash and zsh expand nothing inside), each `'` written `'\''`. */
const shellSafe = (path: string): string => (PLAIN.test(path) ? path : `'${path.split("'").join("'\\''")}'`);

/**
 * What goes on the clipboard (the Mac's rule, and Linux's): one path is its path (as it is when plain, else POSIX single-quoted); several paths are ONE line, space-separated, each handled on
 * its own by the same rule, with no line break anywhere in the text. Null, nothing copied, when no path is given or when any path holds a refused scalar: one refused name refuses the whole drop.
 * A Windows path (`C:\...`) holds a backslash and is therefore refused too. Pasted bare into a shell and followed by Enter the text could still run an executable file: it is meant for an
 * agent's prompt, and the line the island shows says to paste it there.
 *
 * On Windows (`"windows"`) every path is wrapped in double quotes, backslashes kept, so several quoted paths stay unambiguous on one space-separated line. The text is for an agent's prompt, not
 * a shell: the quotes do not stop a PowerShell or cmd paste from acting on `$`, a backtick or `%` (refused). A `"` (or a curly or full-width quote) is refused too. The other refusals are the same, including the `!`, and a path ending in a backslash is refused too.
 * On Windows an empty or non-string entry refuses the whole drop as well.
 */
export function pathsText(paths: unknown, platform: "windows" | "linux" = "linux"): string | null {
  const all: unknown[] = Array.isArray(paths) ? paths : [];
  const list = all.filter((p): p is string => typeof p === "string" && p !== "");
  if (platform === "windows") {
    // An empty or non-string entry refuses the whole drop: nothing is skipped, so the text is never shorter than the drop.
    if (!list.length || list.length !== all.length) return null;
    // Git Bash reads \" in double quotes as an escaped quote, so a trailing backslash would run the next path unquoted.
    if (list.some((p) => REFUSED_WINDOWS.test(p) || p.endsWith("\\"))) return null;
    return list.map((p) => `"${p}"`).join(" ");
  }
  if (!list.length || list.some((p) => REFUSED.test(p))) return null;
  return list.map(shellSafe).join(" ");
}

/** The line the island shows once the path is on the clipboard. It says copied, never sent. */
export const copiedLine = (agentId: string): string => `Copied the path \u2014 paste it into ${agentName(agentId)}`;

/** The line when it could not be: nothing was copied, and it says so. */
export const NOT_COPIED_LINE = "Couldn't copy the path.";
