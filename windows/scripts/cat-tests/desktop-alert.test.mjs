import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";

// The alert (sub-project H, spec §1): an approval or a question that waits takes the cat to the notch, and clearing them sends it back.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const task = (id, state = "idle") => ({ id, name: id, color: "#8AB4F8", state, stepIndex: 0, steps: [], source: "agent", isIntegration: false });

test("State says when an approval or a question is waiting (a pending approval, a chat's, or a pill in that state), and the sleep timer asks State for it (one rule, not a copy)", () => {
  State.tasks = [task("integration_claude"), task("agent_gemini")]; State.pendingApproval = null;
  assert.equal(State.attentionNeeded, false);
  State.tasks[1].state = "question";
  assert.equal(State.attentionNeeded, true);
  State.tasks[1].state = "approval";
  assert.equal(State.attentionNeeded, true);
  State.tasks[1].state = "working";
  assert.equal(State.attentionNeeded, false);
  State.pendingApproval = { requestId: "r", sessionId: "s", tool: "Bash", command: "ls" };
  assert.equal(State.attentionNeeded, true);
  State.pendingApproval = null;
  State.chatApprovals.push({ requestId: "c1", sessionId: "s", tool: "Bash", command: "ls" });
  assert.equal(State.attentionNeeded, true, "a step Claude Code waits to take in a chat counts");
  State.chatApprovals.removeAll();
  assert.equal(State.attentionNeeded, false);
  assert.equal(State.desktopNotchEmpty, false, "the big cat's spot holds the cat until the trip says otherwise");
  const isl = source("island/island.ts");
  assert.match(isl, /blocked: \(\) => State\.attentionNeeded \|\| State\.linkOfferPending,/, "the nap asks State, not its own copy of the rule");
  assert.doesNotMatch(isl, /State\.chatApprovals\.length > 0/, "the rule is written once, in State");
});

test("the brain asks the trip about the alert at every change of State, and a flight in the air follows the notch spot", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /this\.trip\.alert\(desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\), transferOffer: State\.linkOfferPending \}\)\);\s*this\.trip\.notchMoved\(\);/);
  assert.match(b, /State\.subscribe\(\(\) => this\.changed\(\)\);/);
});
