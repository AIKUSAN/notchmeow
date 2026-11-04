// The Companion tab's pure rules (F3a-tauri, Task 12): the name the brain line shows and the text of "What the AI saw last". No DOM, so the tests can read them
// (companion.ts draws the tab and imports these).

import type { Resolution } from "../core/bridge.ts";
import { chipLabel } from "../companion/chrome.ts";

/** The name of the brain a message goes to: the chat's own chip words (Auto · model, Claude's words), or "your AI" when no model has a name. A provider's id is
 * never shown. `authMethod` is Claude Code's, read only when the brain is Claude Code. */
export function brainNameOf(r: Resolution | null | undefined, authMethod: string | null = null): string {
  if (!r || r.empty) return "your AI";
  if (r.provider !== "claudeCode" && !r.modelName) return "your AI";
  return chipLabel(r, authMethod, null);
}

/** The text of "What the AI saw last": the lines joined by a newline, or the sentence for a run that sent nothing. */
export function sawText(lines: readonly string[]): string {
  return lines.length ? lines.join("\n") : "Nothing sent since NotchMeow started.";
}
