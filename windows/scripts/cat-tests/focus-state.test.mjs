import test from "node:test";
import assert from "node:assert/strict";
import { State } from "../../src/core/state.ts";

// The focus marks in State (the Mac's AppState.focusMarks, memory only): a recorded mark dots its pill until the badge, a waiting card, the ten minutes or the
// session's end takes the dot away. Real State, restored afterwards; recording a mark does not notify (handleHook does).
const PILL = "integration_claude";
const T = 5_000_000;
const mark = { sessionId: "S1", pillId: PILL, host: "VS Code", kind: "permission", words: "Runs", at: T };

test("a stepped-back mark dots its pill, and the dot goes with a badge, a waiting card, the ten minutes or the session's end", () => {
  const saved = { tasks: State.tasks, marks: State.focusMarks, pending: State.pendingApproval };
  let notified = 0;
  const off = State.subscribe(() => { notified++; });
  try {
    State.tasks = [{ id: PILL, name: "Claude Code", state: "working", steps: [], stepIndex: 0, pillBadge: null }];
    State.pendingApproval = null;
    State.focusMarks = [];

    State.recordFocusMark(mark);
    assert.equal(notified, 0, "recording a mark does not notify");
    assert.equal(State.focusDot(PILL, T + 1), true, "the dot is on");
    assert.equal(State.focusDot(PILL, T + 599_999), true, "still on just before the ten minutes");

    State.tasks[0].pillBadge = "finished";
    assert.equal(State.focusDot(PILL, T + 1), false, "a badge takes the dot");
    State.tasks[0].pillBadge = null;
    assert.equal(State.focusDot(PILL, T + 1), true);

    State.pendingApproval = { pillId: PILL };
    assert.equal(State.focusDot(PILL, T + 1), false, "a waiting card takes the dot");
    State.pendingApproval = null;

    assert.equal(State.focusDot(PILL, T + 600_001), false, "ten minutes on, the dot is gone");

    State.recordFocusMark(mark);
    State.endFocusMarks("S1", "Stop", "");
    assert.equal(State.focusDot(PILL, T + 1), false, "the session's Stop ends the mark");
  } finally {
    off();
    State.tasks = saved.tasks;
    State.focusMarks = saved.marks;
    State.pendingApproval = saved.pending;
  }
});
