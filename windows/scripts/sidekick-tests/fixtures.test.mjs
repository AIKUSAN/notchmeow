import test from "node:test";
import assert from "node:assert/strict";
import * as core from "../../src/sidekick/core.ts";
import { load } from "./util.mjs";

// Every fixture of tests/fixtures/sidekick/ replayed against the app's own copy of the rules (src/sidekick/core.ts), in the app's own language.
// The cases are the contract's: shared/sidekick-core.js decides, and a disagreement here is the app's bug.

test("explain: every row of explain-cases.json gives its risk, reason, line and target", () => {
  const fx = load("explain-cases.json");
  assert.ok(fx.cases.length >= 500, `${fx.cases.length} cases`);
  assert.deepEqual(core.REASONS.map((r) => ({ id: r.id, risk: r.risk, line: r.line })), fx.reasons);
  for (const c of fx.cases) {
    const got = core.explain(c.agent, c.tool ?? undefined, c.input ?? undefined, c.cwd, c.home);
    assert.deepEqual([got.risk, got.reasonId, got.line, got.target], [c.risk, c.reasonId, c.line, c.target], c.name);
  }
});

test("eventFrom and ledgerApply: every payload gives its event, every sequence its ledger", () => {
  const fx = load("hook-cases.json");
  for (const c of fx.cases) assert.deepEqual(core.eventFrom(c.payload, c.now, c.opts), c.event, c.name);
  for (const s of fx.sequences) {
    let ledger = core.emptyLedger();
    for (const st of s.steps) {
      const ev = st.answered ? core.approvalAnsweredEvent(st.answered.agentId, st.answered.sessionId, st.at) : core.eventFrom(st.payload, st.at, st.opts);
      ledger = core.ledgerApply(ledger, ev);
    }
    assert.deepEqual(ledger, s.ledger, s.name);
  }
});

test("stuckStep and nudgeText: every timeline gives its nudge, deadline and words", () => {
  const fx = load("stuck-cases.json");
  assert.deepEqual(core.STUCK, fx.thresholds);
  assert.deepEqual(core.NUDGE_KINDS, fx.kinds);
  for (const c of fx.cases) {
    let ledger = core.emptyLedger();
    for (const st of c.steps) {
      if (st.payload) { ledger = core.ledgerApply(ledger, core.eventFrom(st.payload, st.at)); continue; }
      const ctx = st.probe.ctx, r = core.stuckStep(ledger, st.at, ctx);
      assert.equal(r.nudge ? r.nudge.kind : null, st.expect, `${c.name} @${st.at}`);
      if (st.nextAt !== undefined) assert.equal(r.nextAt, st.nextAt, `${c.name} @${st.at} nextAt`);
      if (st.text !== undefined) assert.equal(r.nudge ? core.nudgeText(r.nudge, ledger, st.at, ctx) : null, st.text, `${c.name} @${st.at} words`);
      if (st.probe.mark && r.nudge) ledger = core.markNudged(ledger, r.nudge.key, st.at);
    }
  }
});

test("recapOf, statusOf and matchStatusQuestion: every snapshot and every message gives what it records", () => {
  const recap = load("recap-cases.json"), status = load("status-cases.json");
  assert.equal(core.RECAP.MIN_AWAY_MS, recap.min);
  for (const c of recap.cases) assert.deepEqual(core.recapOf(c.snapshot), c.recap, c.name);
  for (const c of status.cases) assert.deepEqual(core.statusOf(c.snapshot, c.agent), c.status, c.name);
  for (const m of status.matcher) assert.deepEqual(core.matchStatusQuestion(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
});

test("dismiss, unmute and cleanSidekickSettings: every operation and every stored value gives what it records", () => {
  const dismiss = load("dismiss-cases.json"), settings = load("settings-cases.json");
  assert.deepEqual(core.DISMISS_KINDS, dismiss.kinds);
  assert.equal(core.MUTE_AT, dismiss.muteAt);
  for (const c of dismiss.cases) {
    let state = c.start;
    c.ops.forEach((o, i) => {
      state = core[o.op](state, o.kind);
      assert.deepEqual([state, core.DISMISS_KINDS.filter((k) => core.muted(state, k))], [c.trail[i].state, c.trail[i].muted], c.name);
    });
  }
  for (const c of settings.cases) assert.deepEqual(core.cleanSidekickSettings(c.raw), c.clean, c.name);
});

test("presenceStep and shouldShow: every signal and every gate input gives what it records", () => {
  const presence = load("presence-cases.json"), show = load("show-cases.json");
  assert.deepEqual(core.IDLE, presence.idle);
  assert.deepEqual(core.HOLD_MS, show.holdMs);
  assert.equal(core.NOTE_GAP_MS, show.noteGapMs);
  for (const c of presence.cases) {
    let state = c.start;
    for (const st of c.steps) {
      const r = core.presenceStep(state, st.signal, st.at);
      assert.deepEqual(r, { state: st.state, back: st.back }, `${c.name} @${st.at}`);
      state = r.state;
    }
  }
  for (const c of show.cases) assert.deepEqual(core.shouldShow(c.input), c.show, c.name);
});

test("acceptNicerLine: every sentence is accepted or refused as it records", () => {
  const fx = load("voice-cases.json");
  for (const c of fx.cases) assert.equal(core.acceptNicerLine(c.line, c.facts), c.ok, c.name);
});

test("a number that is not a number never gets through: NaN and Infinity in the times, the counts and the facts", () => {
  const ev = core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S", tool_name: "Bash", tool_input: { command: "ls" } }, 1000);
  assert.ok(ev);
  assert.equal(core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S" }, Number.NaN), null);
  assert.equal(core.eventFrom({ hook_event_name: "PostToolUse", session_id: "S" }, Number.POSITIVE_INFINITY), null);
  const ledger = core.ledgerApply(core.emptyLedger(), ev);
  assert.deepEqual(core.stuckStep(ledger, Number.NaN, {}), { nudge: null, nextAt: null });
  assert.equal(core.recapOf({ awaySince: Number.NaN, now: 1e9, sessions: ledger.sessions }), null);
  assert.equal(core.recapOf({ awaySince: 0, now: Number.POSITIVE_INFINITY, sessions: ledger.sessions }), null);
  assert.equal(core.presenceStep(core.presenceInit(), { type: "idle", seconds: Number.POSITIVE_INFINITY }, 1000).back, false);
  assert.equal(core.acceptNicerLine("Claude Code ran 3 steps.", [{ agent: "Claude Code", steps: Number.POSITIVE_INFINITY }]), false);
  assert.equal(core.acceptNicerLine("Claude Code ran 3 steps.", [{ agent: "Claude Code", steps: 3 }]), true);
});
