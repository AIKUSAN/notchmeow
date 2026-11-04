// The line under a permission request (sub-project F1, spec "Risk rules" and "The permission line"): how risky it is and a fixed sentence saying so, from the contract's `explain`.
// It labels. It never allows, denies or blocks: only the user's click does. The one thing this adds to the rules is the Windows relay's cut: it cuts every string at 2000 bytes, so a long
// command reaches the app without its end, and a label that read only the beginning must not call it safe. Pure; loaded by the plain-Node checks.

import { REASONS, explain } from "./core.ts";
import type { Explained, Risk } from "./core.ts";

/** The relay's longest string (hook/src/main.rs `MAX_FIELD_LEN`): a longer one arrives cut at this many bytes, with "…" after it. */
export const RELAY_CUT_BYTES = 2000;

const SHELL_TOOLS = new Set(["Bash", "PowerShell", "run_shell_command", "shell", "local_shell", "exec_command"]);
/** The fields that name what a non-shell tool touches. A cut file body (`content`, `new_string`) changes nothing about the label, so it is not looked at. */
const PATH_FIELDS = ["file_path", "path", "absolute_path", "notebook_path", "paths", "dir_path", "target_file"];

const utf8Bytes = (s: string): number => new TextEncoder().encode(s).length;
const isCut = (v: unknown): boolean => typeof v === "string" && v.endsWith("…") && utf8Bytes(v) >= RELAY_CUT_BYTES;

/** Whether the part of a request that the label depends on came through the relay cut: the command of a shell tool, a path of any other tool. */
export function wasCut(tool: string, input: unknown): boolean {
  if (input === null || typeof input !== "object" || Array.isArray(input)) return false;
  const o = input as Record<string, unknown>;
  if (SHELL_TOOLS.has(tool)) return isCut(o.command) || (Array.isArray(o.command) && o.command.some(isCut));
  return PATH_FIELDS.some((k) => (Array.isArray(o[k]) ? (o[k] as unknown[]).some(isCut) : isCut(o[k])));
}

const unsure = (): Explained => {
  const r = REASONS.find((x) => x.id === "unsure")!;
  return { risk: r.risk, reasonId: r.id, line: r.line, target: "" };
};

/**
 * `explain` of the contract for one permission request, `cwd` and `home` as the app knows them. A request whose command or path was cut by the relay is at least `unsure` (medium): what
 * the rules read is only its beginning. A label that is already medium or high stays what it is.
 */
export function explainRequest(tool: string, input: unknown, cwd: string, home: string): Explained {
  const got = explain("integration_claude", tool, input, cwd, home);
  return got.risk === "low" && wasCut(tool, input) ? unsure() : got;
}

/** The words of the orange badge: only a high risk has one. Medium and low show the grey line alone. */
export const badgeText = (risk: Risk | null | undefined): string | null => (risk === "high" ? "High risk" : null);
