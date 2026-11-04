// One pairing conversation (docs/LINK-CONTRACT.md, "The pairing code"), on either side. The rules are the pure machines of `pairing.rs`, run one event at a time; this file only does the I/O
// around them: the preamble, the three `XX` handshake messages (commitment, hello with the responder's nonce, hello with the initiator's reveal), the code, the user's answer, the other side's
// answer, and the two minutes of the window. Nothing is stored here: a `Paired` outcome says that **both users said yes**, and the caller writes the key (`Keystore::add` re-checks the paired
// map at that moment). Nothing here reads a clock or draws a random number of its own: `clock` (whole milliseconds, monotonic) and the nonce come in, so a test can run both sides in one
// process. The Mac's twin is LinkPairRun.swift.

use std::sync::Arc;

use tokio::sync::mpsc;
use tokio::time::Duration;

use super::bytes::{hex, key32, id16};
use super::channel::{close_within, handshake_receive, handshake_send, Channel, IdleWatch, LinkError, Transport};
use super::frames::{decode_hello, encode_hello, encode_preamble, Frame, Mode};
use super::identity::{Identity, Peer};
use super::noise::{Handshake, Pattern, PROLOGUE};
use super::pairing::{self, IEvent, IPhase, Initiator, Notify, REvent, RPhase, Responder, Reveal, Say};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairOutcome {
    Paired(Peer),
    /// A user said no: this machine's (`by_me`) or the other's.
    Declined { by_me: bool },
    /// A rule or the wire refused: a `pairing::Refusal` word, or "closed", "handshake", "unexpected-frame".
    Refused(String),
}

/// The handshake of a pairing (the first record to the third message) has this long, on either side: a machine that connects and then says nothing does not hold a pairing. The machines of
/// `pairing.rs` have no clock of their own for it (their window only starts with the commitment), so the run owns it, as it owns the two minutes after the code.
pub const HANDSHAKE_MS: u64 = 10_000;
/// A frame this side sends, and the close at the end, are waited for this long (the same 2 s as the transfers).
const GRACE_MS: u64 = 2_000;

/// Cuts the transport when the handshake takes longer than `HANDSHAKE_MS`, which fails the read the run is waiting in. Stopped when the handshake is over, and by being dropped.
fn handshake_watch<T: Transport>(transport: &Arc<T>) -> IdleWatch {
    let t = transport.clone();
    IdleWatch::new(HANDSHAKE_MS, move || t.abort())
}

/// Tells the service what happens inside a pairing.
#[derive(Clone)]
pub struct PairHooks {
    /// The code is known: show it, with the other machine's authenticated name.
    pub show_code: Arc<dyn Fn(String, String) + Send + Sync>,
    /// The handshake is over (the other side is authenticated); the connection no longer needs the listener's watchdog.
    pub handshake_done: Arc<dyn Fn() + Send + Sync>,
}

/// A frame the pairing connection may carry, a click, the end of the window or the end of the connection.
pub(crate) enum Event {
    User(bool),
    Frame(Frame),
    Closed,
    WindowEnded,
}

/// What the service holds to answer a pairing: the click on "They match" or "No", and the cancel that comes with closing the card.
#[derive(Clone)]
pub struct PairHandle {
    tx: mpsc::UnboundedSender<Event>,
}

impl PairHandle {
    pub fn answer(&self, yes: bool) {
        let _ = self.tx.send(Event::User(yes));
    }
    /// The user closed the card: a no, and the conversation ends.
    pub fn cancel(&self) {
        let _ = self.tx.send(Event::User(false));
    }
}

pub struct PairInbox {
    tx: mpsc::UnboundedSender<Event>,
    rx: mpsc::UnboundedReceiver<Event>,
}

pub fn pair_channel() -> (PairHandle, PairInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    (PairHandle { tx: tx.clone() }, PairInbox { tx, rx })
}

pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;

enum Machine<'a> {
    Initiator(&'a mut Initiator),
    Responder(&'a mut Responder),
}

impl Machine<'_> {
    /// Steps the machine with the user's click or the other side's answer; what it says is (notify, send, because).
    fn answer(&mut self, mine: bool, yes: bool, now: i64) -> (Option<Notify>, Vec<Say>, Option<pairing::Refusal>) {
        match self {
            Machine::Initiator(m) => {
                let o = pairing::initiator_step(m, &if mine { IEvent::User { yes, now } } else { IEvent::Peer { yes, now } });
                **m = o.state;
                (o.notify, o.send, o.because)
            }
            Machine::Responder(m) => {
                let o = pairing::responder_step(m, &if mine { REvent::User { yes, now } } else { REvent::Peer { yes, now } });
                **m = o.state;
                (o.notify, o.send, o.because)
            }
        }
    }
}

/// An incoming pairing connection, behind the gate: when the gate is closed nothing is sent and the connection is closed, as for any other refused hello, and nobody sees a card. The
/// service uses this one function for every incoming pairing, so the rule is tested where it is applied. None when refused.
#[allow(clippy::too_many_arguments)]
pub async fn run_incoming<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, gate: &pairing::Gate, state: Responder, hooks: &PairHooks, inbox: PairInbox) -> Option<(PairOutcome, Responder)> {
    if !gate.allows(Some(clock())) {
        close_within(&transport, GRACE_MS).await;
        return None;
    }
    Some(run_responder(transport, identity, nonce, clock, state, hooks, inbox).await)
}

pub async fn run_initiator<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, start: Initiator, hooks: &PairHooks, inbox: PairInbox) -> (PairOutcome, Initiator) {
    let mut st = start;
    let outcome = match initiate(&transport, identity, nonce, &clock, &mut st, hooks, inbox).await {
        Ok(o) => o,
        Err(_) => {
            st.phase = IPhase::Idle;
            PairOutcome::Refused("handshake".into())
        }
    };
    close_within(&transport, GRACE_MS).await;
    (outcome, st)
}

async fn initiate<T: Transport>(transport: &Arc<T>, identity: &Identity, nonce: [u8; 32], clock: &Clock, st: &mut Initiator, hooks: &PairHooks, inbox: PairInbox) -> Result<PairOutcome, LinkError> {
    let shake = handshake_watch(transport);
    let mut hs = Handshake::new(Pattern::Xx, true, &identity.key, None, PROLOGUE, None)?;
    let o = pairing::initiator_step(st, &IEvent::Start { nonce: hex(&nonce), static_key: hex(&identity.public), now: clock() });
    *st = o.state;
    if let Some(why) = o.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let Some(Say::Commit(commit_hex)) = o.send.first() else { return Ok(PairOutcome::Refused("handshake".into())) };
    let commit = key32(commit_hex).ok_or_else(|| LinkError::Violation("commit".into()))?;
    transport.send(encode_preamble(Mode::Pair, &[0; 16])).await?;
    handshake_send(&**transport, &mut hs, &commit).await?;
    let hello = decode_hello(&handshake_receive(&**transport, &mut hs).await?)?;
    let remote = hs.remote_static().ok_or_else(|| LinkError::Violation("no remote key".into()))?;
    let o2 = pairing::initiator_step(st, &IEvent::Nonce { nonce: hex(&hello.nonce), peer_static: hex(&remote), peer_id: Some(hex(&hello.id)), now: clock() });
    *st = o2.state;
    if let Some(why) = o2.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let my_id = id16(&identity.device_id).ok_or_else(|| LinkError::Violation("device id".into()))?;
    let reveal = encode_hello(&my_id, &nonce, &identity.name)?;
    handshake_send(&**transport, &mut hs, &reveal).await?;
    let noise = hs.finish()?;
    shake.stop();
    let IPhase::Coded { start: started_at, code, .. } = st.phase.clone() else { return Err(LinkError::Violation("no code".into())) };
    let peer = Peer { id: hex(&hello.id), name: hello.name.clone(), key: hex(&remote), at: unix_seconds() };
    (hooks.handshake_done)();
    (hooks.show_code)(code, hello.name);
    let channel = Arc::new(Channel::new(transport.clone(), noise));
    Ok(answers(channel, started_at, peer, clock, Machine::Initiator(st), inbox).await)
}

/// The preamble was read already (the listener reads it to tell a pairing from a transfer).
pub async fn run_responder<T: Transport>(transport: Arc<T>, identity: &Identity, nonce: [u8; 32], clock: Clock, start: Responder, hooks: &PairHooks, inbox: PairInbox) -> (PairOutcome, Responder) {
    let mut st = start;
    let outcome = match respond(&transport, identity, nonce, &clock, &mut st, hooks, inbox).await {
        Ok(o) => o,
        Err(_) => {
            st.phase = RPhase::Idle;
            PairOutcome::Refused("handshake".into())
        }
    };
    close_within(&transport, GRACE_MS).await;
    (outcome, st)
}

async fn respond<T: Transport>(transport: &Arc<T>, identity: &Identity, nonce: [u8; 32], clock: &Clock, st: &mut Responder, hooks: &PairHooks, inbox: PairInbox) -> Result<PairOutcome, LinkError> {
    let shake = handshake_watch(transport);
    let mut hs = Handshake::new(Pattern::Xx, false, &identity.key, None, PROLOGUE, None)?;
    let commit = handshake_receive(&**transport, &mut hs).await?;
    let o = pairing::responder_step(st, &REvent::Commit { commit: hex(&commit), nonce: hex(&nonce), now: clock() });
    *st = o.state;
    if let Some(why) = o.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let my_id = id16(&identity.device_id).ok_or_else(|| LinkError::Violation("device id".into()))?;
    handshake_send(&**transport, &mut hs, &encode_hello(&my_id, &nonce, &identity.name)?).await?;
    let reveal = decode_hello(&handshake_receive(&**transport, &mut hs).await?)?;
    let remote = hs.remote_static().ok_or_else(|| LinkError::Violation("no remote key".into()))?;
    let o2 = pairing::responder_step(
        st,
        &REvent::Reveal { reveal: Reveal { nonce: hex(&reveal.nonce), static_key: hex(&remote), own: hex(&identity.public), peer_id: Some(hex(&reveal.id)) }, now: clock() },
    );
    *st = o2.state;
    if let Some(why) = o2.because {
        return Ok(PairOutcome::Refused(why.as_str().into()));
    }
    let noise = hs.finish()?;
    shake.stop();
    let RPhase::Coded { start: started_at, code, .. } = st.phase.clone() else { return Err(LinkError::Violation("no code".into())) };
    let peer = Peer { id: hex(&reveal.id), name: reveal.name.clone(), key: hex(&remote), at: unix_seconds() };
    (hooks.handshake_done)();
    (hooks.show_code)(code, reveal.name);
    let channel = Arc::new(Channel::new(transport.clone(), noise));
    Ok(answers(channel, started_at, peer, clock, Machine::Responder(st), inbox).await)
}

fn unix_seconds() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// After the code is shown: the user's click and the other side's `pair-yes` or `pair-no`, in either order, inside the window. The only frames a pairing connection may carry.
async fn answers<T: Transport>(channel: Arc<Channel<T>>, window_start: i64, peer: Peer, clock: &Clock, mut machine: Machine<'_>, inbox: PairInbox) -> PairOutcome {
    let PairInbox { tx, mut rx } = inbox;
    let reader = {
        let (channel, tx) = (channel.clone(), tx.clone());
        tokio::spawn(async move {
            loop {
                match channel.receive_frame().await {
                    Ok(f) => {
                        if tx.send(Event::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = tx.send(Event::Closed);
                        return;
                    }
                }
            }
        })
    };
    let remaining = (pairing::WINDOW_MS - (clock() - window_start)).max(0) as u64;
    let timer = {
        let tx = tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(remaining)).await;
            let _ = tx.send(Event::WindowEnded);
        })
    };
    let outcome = loop {
        let Some(event) = rx.recv().await else { break PairOutcome::Refused("closed".into()) };
        let (mine, yes) = match event {
            Event::User(yes) => (true, yes),
            Event::Frame(Frame::PairYes) => (false, true),
            Event::Frame(Frame::PairNo) => (false, false),
            Event::Frame(_) => break PairOutcome::Refused("unexpected-frame".into()),
            Event::Closed => break PairOutcome::Refused("closed".into()),
            Event::WindowEnded => break PairOutcome::Refused(pairing::Refusal::WindowClosed.as_str().into()),
        };
        let (notify, send, because) = machine.answer(mine, yes, clock());
        // Our own answer must leave before anything is stored: a pair-yes that never left would leave the other side waiting for it alone, with a key stored on this side only.
        let mut failed = false;
        for s in &send {
            if let Say::Pair(y) = s {
                if channel.send_within(&if *y { Frame::PairYes } else { Frame::PairNo }, GRACE_MS).await.is_err() {
                    failed = true;
                }
            }
        }
        if failed {
            break PairOutcome::Refused("closed".into());
        }
        match notify {
            Some(Notify::Store) => break PairOutcome::Paired(peer),
            Some(Notify::Discard) => {
                break if because == Some(pairing::Refusal::SaidNo) { PairOutcome::Declined { by_me: mine } } else { PairOutcome::Refused(because.map_or("discard", |b| b.as_str()).into()) };
            }
            _ => {}
        }
    };
    reader.abort();
    timer.abort();
    outcome
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::channel::{MemoryEnd, StuckClose};
    use crate::link::frames::decode_preamble;
    use crate::link::noise::{generate_static, public_of};
    use crate::link::pairing::{Gate, Ids, OwnId};
    use std::collections::BTreeMap;
    use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
    use std::sync::Mutex as StdMutex;

    fn identity(tag: u8, name: &str) -> Identity {
        let (key, public) = generate_static().unwrap();
        assert_eq!(public_of(&key).unwrap(), public);
        Identity { device_id: hex(&[tag; 16]), name: name.to_string(), key, public }
    }

    struct Side {
        shown: Arc<StdMutex<Vec<(String, String)>>>,
        done: Arc<AtomicUsize>,
        hooks: PairHooks,
    }

    fn side() -> Side {
        let shown = Arc::new(StdMutex::new(Vec::new()));
        let done = Arc::new(AtomicUsize::new(0));
        let (s, d) = (shown.clone(), done.clone());
        let hooks = PairHooks { show_code: Arc::new(move |c, n| s.lock().unwrap().push((c, n))), handshake_done: Arc::new(move || { d.fetch_add(1, Ordering::SeqCst); }) };
        Side { shown, done, hooks }
    }

    fn clock() -> (Clock, Arc<AtomicI64>) {
        let t = Arc::new(AtomicI64::new(1_000));
        let c = t.clone();
        (Arc::new(move || c.load(Ordering::SeqCst)), t)
    }

    /// A test that waits on a run ends by itself even when the run does not: an await that takes 20 real seconds is a failure, not a hang (paused-time tests never reach it).
    async fn within<F: std::future::Future>(f: F) -> F::Output {
        tokio::time::timeout(Duration::from_secs(20), f).await.expect("took longer than 20 s")
    }

    async fn wait_for_code(s: &Side) -> String {
        for _ in 0..2000 {
            if let Some((c, _)) = s.shown.lock().unwrap().first() {
                return c.clone();
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        panic!("no code was shown");
    }

    struct Run {
        init: tokio::task::JoinHandle<(PairOutcome, Initiator)>,
        resp: tokio::task::JoinHandle<Option<(PairOutcome, Responder)>>,
        ih: PairHandle,
        rh: PairHandle,
        i_side: Side,
        r_side: Side,
    }

    fn start(i_id: &Identity, r_id: &Identity, i_state: Initiator, r_state: Responder, gate: Gate, clk: Clock) -> Run {
        let (a, b) = MemoryEnd::pair();
        let (i_side, r_side) = (side(), side());
        let (ih, ii) = pair_channel();
        let (rh, ri) = pair_channel();
        let (i_id, r_id, i_hooks, r_hooks, c2) = (i_id.clone(), r_id.clone(), i_side.hooks.clone(), r_side.hooks.clone(), clk.clone());
        let init = tokio::spawn(async move { run_initiator(a, &i_id, [0xA1; 32], clk, i_state, &i_hooks, ii).await });
        let resp = tokio::spawn(async move {
            // The listener reads the preamble first.
            let pre = decode_preamble(&b.receive().await.unwrap()).unwrap();
            assert_eq!(pre.mode, Mode::Pair);
            run_incoming(b, &r_id, [0xB1; 32], c2, &gate, r_state, &r_hooks, ri).await
        });
        Run { init, resp, ih, rh, i_side, r_side }
    }

    fn open_gate() -> Gate {
        let mut g = Gate::default();
        g.devices_appeared();
        g
    }

    #[tokio::test]
    async fn both_users_say_they_match_and_each_side_keeps_the_other() {
        let (i, r) = (identity(1, "Sam's MacBook Pro"), identity(2, "Desk PC"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        let (ci, cr) = (wait_for_code(&run.i_side).await, wait_for_code(&run.r_side).await);
        assert_eq!(ci, cr, "both screens show the same six digits");
        assert_eq!(ci.len(), 6);
        assert_eq!(run.i_side.shown.lock().unwrap()[0].1, "Desk PC", "the initiator sees the responder's authenticated name");
        assert_eq!(run.r_side.shown.lock().unwrap()[0].1, "Sam's MacBook Pro");
        run.ih.answer(true);
        run.rh.answer(true);
        let (io, _) = run.init.await.unwrap();
        let (ro, _) = run.resp.await.unwrap().unwrap();
        assert_eq!(io, PairOutcome::Paired(Peer { id: r.device_id.clone(), name: "Desk PC".into(), key: hex(&r.public), at: match &io { PairOutcome::Paired(p) => p.at, _ => 0 } }));
        match ro {
            PairOutcome::Paired(p) => assert_eq!((p.id, p.name, p.key), (i.device_id.clone(), "Sam's MacBook Pro".to_string(), hex(&i.public))),
            other => panic!("{other:?}"),
        }
        assert_eq!(run.i_side.done.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn one_no_stores_nothing_on_either_side() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        run.ih.answer(true);
        run.rh.answer(false);
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Declined { by_me: false });
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Declined { by_me: true });
    }

    #[tokio::test]
    async fn closing_the_card_is_a_no() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        run.ih.cancel();
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Declined { by_me: true });
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Declined { by_me: false });
    }

    #[tokio::test]
    async fn outside_the_gate_nothing_is_sent_and_no_card_is_shown() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), Gate::default(), clk);
        assert!(run.resp.await.unwrap().is_none(), "refused silently");
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("handshake".into()), "the initiator sees only a closed connection");
        assert!(run.r_side.shown.lock().unwrap().is_empty() && run.i_side.shown.lock().unwrap().is_empty());
        assert_eq!(run.r_side.done.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn the_gate_is_open_for_two_minutes_after_a_click_and_not_a_millisecond_longer() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        for (now, runs) in [(121_000i64 - 1, true), (121_000, false)] {
            let mut gate = Gate::default();
            gate.pair_clicked(1_000);
            let t = Arc::new(AtomicI64::new(now));
            let c = t.clone();
            let clk: Clock = Arc::new(move || c.load(Ordering::SeqCst));
            let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), gate, clk);
            if runs {
                wait_for_code(&run.r_side).await;
                run.rh.answer(false);
                run.ih.answer(false);
            }
            let got = run.resp.await.unwrap();
            assert_eq!(got.is_some(), runs, "at {now}");
            let _ = run.init.await;
        }
    }

    #[tokio::test(start_paused = true)]
    async fn nobody_answering_ends_it_when_the_window_closes() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, t) = clock();
        let run = start(&i, &r, Initiator::new(Ids::default()), Responder::new(Ids::default()), open_gate(), clk);
        wait_for_code(&run.i_side).await;
        wait_for_code(&run.r_side).await;
        t.fetch_add(120_000, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(120_001)).await;
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("window-closed".into()));
        assert_eq!(run.resp.await.unwrap().unwrap().0, PairOutcome::Refused("window-closed".into()));
    }

    #[tokio::test]
    async fn a_second_attempt_inside_30_seconds_is_refused() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, t) = clock();
        let mut machine = Initiator::new(Ids::default());
        machine.last = Some(t.load(Ordering::SeqCst) - 29_999);
        let run = start(&i, &r, machine, Responder::new(Ids::default()), open_gate(), clk);
        let (io, _) = run.init.await.unwrap();
        assert_eq!(io, PairOutcome::Refused("attempt-too-soon".into()));
        let _ = run.resp.await;
    }

    #[tokio::test]
    async fn an_id_paired_under_another_key_is_refused_by_the_initiator() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let mut paired = BTreeMap::new();
        paired.insert(r.device_id.clone(), hex(&[9u8; 32]));
        let ids = Ids { own_id: OwnId::Id(i.device_id.clone()), paired: Some(paired) };
        let run = start(&i, &r, Initiator::new(ids), Responder::new(Ids::default()), open_gate(), clk);
        assert_eq!(run.init.await.unwrap().0, PairOutcome::Refused("id-key-mismatch".into()));
        assert_eq!(run.r_side.shown.lock().unwrap().len(), 0);
        let _ = run.resp.await;
    }

    #[tokio::test(start_paused = true)]
    async fn a_peer_that_says_nothing_after_its_preamble_is_let_go_after_10_seconds() {
        let r = identity(2, "B");
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let (_rh, ri) = pair_channel();
        let (hooks, gate) = (side().hooks, open_gate());
        let task = tokio::spawn(async move {
            decode_preamble(&b.receive().await.unwrap()).unwrap();
            run_incoming(b, &r, [0xB1; 32], clk, &gate, Responder::new(Ids::default()), &hooks, ri).await
        });
        a.send(encode_preamble(Mode::Pair, &[0; 16])).await.unwrap();
        tokio::time::sleep(Duration::from_millis(9_900)).await;
        assert!(!task.is_finished());
        tokio::time::sleep(Duration::from_millis(200)).await;
        tokio::task::yield_now().await;
        assert!(task.is_finished(), "let go at 10 s, not later");
        assert_eq!(within(task).await.unwrap().unwrap().0, PairOutcome::Refused("handshake".into()));
        assert_eq!(within(a.receive()).await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test(start_paused = true)]
    async fn a_machine_that_takes_the_connection_and_says_nothing_ends_the_initiator_after_10_seconds() {
        let i = identity(1, "A");
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let (_ih, ii) = pair_channel();
        let hooks = side().hooks;
        let task = tokio::spawn(async move { run_initiator(a, &i, [0xA1; 32], clk, Initiator::new(Ids::default()), &hooks, ii).await });
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        b.receive().await.unwrap(); // the commitment, and then nothing
        tokio::time::sleep(Duration::from_millis(9_900)).await;
        assert!(!task.is_finished());
        tokio::time::sleep(Duration::from_millis(200)).await;
        tokio::task::yield_now().await;
        assert!(task.is_finished(), "let go at 10 s, not later");
        assert_eq!(within(task).await.unwrap().0, PairOutcome::Refused("handshake".into()));
    }

    #[tokio::test]
    async fn a_damaged_handshake_message_ends_the_pairing_and_nothing_is_sent_after_it() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let r_side = side();
        let (_rh, ri) = pair_channel();
        let (hooks, gate) = (r_side.hooks.clone(), open_gate());
        let task = tokio::spawn(async move {
            decode_preamble(&b.receive().await.unwrap()).unwrap();
            run_incoming(b, &r, [0xB1; 32], clk, &gate, Responder::new(Ids::default()), &hooks, ri).await
        });
        a.send(encode_preamble(Mode::Pair, &[0; 16])).await.unwrap();
        let mut hs = Handshake::new(Pattern::Xx, true, &i.key, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hs, &pairing::commit_of(&[0xA1; 32], &i.public)).await.unwrap();
        handshake_receive(&*a, &mut hs).await.unwrap();
        let mut reveal = hs.write(&encode_hello(&id16(&i.device_id).unwrap(), &[0xA1; 32], &i.name).unwrap()).unwrap();
        let last = reveal.len() - 1;
        reveal[last] ^= 1; // the third message, one bit off
        a.send(reveal).await.unwrap();
        assert_eq!(within(task).await.unwrap().unwrap().0, PairOutcome::Refused("handshake".into()));
        assert_eq!(within(a.receive()).await.unwrap_err(), LinkError::Closed, "nothing came back after the damage");
        assert!(r_side.shown.lock().unwrap().is_empty() && r_side.done.load(Ordering::SeqCst) == 0);
    }

    #[tokio::test]
    async fn a_damaged_message_after_the_handshake_ends_the_pairing_and_nothing_is_sent_after_it() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let (_ih, ii) = pair_channel();
        let hooks = side().hooks;
        let i2 = i.clone();
        let init = tokio::spawn(async move { run_initiator(a, &i2, [0xA1; 32], clk, Initiator::new(Ids::default()), &hooks, ii).await });
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let mut hs = Handshake::new(Pattern::Xx, false, &r.key, None, PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        handshake_send(&*b, &mut hs, &encode_hello(&id16(&r.device_id).unwrap(), &[0xB1; 32], &r.name).unwrap()).await.unwrap();
        decode_hello(&handshake_receive(&*b, &mut hs).await.unwrap()).unwrap();
        b.send(vec![7; 40]).await.unwrap(); // a record that does not open
        assert_eq!(within(init).await.unwrap().0, PairOutcome::Refused("closed".into()));
        assert_eq!(within(b.receive()).await.unwrap_err(), LinkError::Closed, "no pair-no and no other frame went out after the damage");
    }

    /// Alive 100 ms before the 2 s grace, over within 100 ms after it (paused time): the close was cut, it did not end by itself (`StuckClose` never ends its close).
    async fn closed_at_the_grace<R: std::fmt::Debug>(task: &mut tokio::task::JoinHandle<R>) -> R {
        tokio::time::sleep(Duration::from_millis(1_900)).await;
        assert!(!task.is_finished(), "alive 100 ms before the grace");
        tokio::time::sleep(Duration::from_millis(200)).await;
        tokio::time::timeout(Duration::from_millis(100), task).await.expect("not over within 100 ms of the grace").unwrap()
    }

    #[tokio::test(start_paused = true)]
    async fn a_refused_connection_whose_close_is_stuck_is_cut_after_the_grace() {
        let r = identity(2, "B");
        let (clk, _) = clock();
        let (_a, b) = MemoryEnd::pair();
        let stuck = StuckClose::new(b);
        let (_rh, ri) = pair_channel();
        let hooks = side().hooks;
        let mut task = tokio::spawn(async move { run_incoming(stuck, &r, [0xB1; 32], clk, &Gate::default(), Responder::new(Ids::default()), &hooks, ri).await });
        assert!(closed_at_the_grace(&mut task).await.is_none(), "refused silently");
    }

    #[tokio::test(start_paused = true)]
    async fn an_initiator_whose_close_is_stuck_is_cut_after_the_grace() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let stuck = StuckClose::new(a);
        let (_ih, ii) = pair_channel();
        let hooks = side().hooks;
        let mut init = tokio::spawn(async move { run_initiator(stuck, &i, [0xA1; 32], clk, Initiator::new(Ids::default()), &hooks, ii).await });
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let mut hs = Handshake::new(Pattern::Xx, false, &r.key, None, PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        handshake_send(&*b, &mut hs, &encode_hello(&id16(&r.device_id).unwrap(), &[0xB1; 32], &r.name).unwrap()).await.unwrap();
        decode_hello(&handshake_receive(&*b, &mut hs).await.unwrap()).unwrap();
        b.send(vec![7; 40]).await.unwrap(); // a record that does not open: the pairing ends and its close has nowhere to go
        assert_eq!(closed_at_the_grace(&mut init).await.0, PairOutcome::Refused("closed".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn a_responder_whose_close_is_stuck_is_cut_after_the_grace() {
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let stuck = StuckClose::new(b);
        let (_rh, ri) = pair_channel();
        let (hooks, gate) = (side().hooks, open_gate());
        let mut task = tokio::spawn(async move {
            decode_preamble(&stuck.receive().await.unwrap()).unwrap();
            run_incoming(stuck, &r, [0xB1; 32], clk, &gate, Responder::new(Ids::default()), &hooks, ri).await
        });
        a.send(encode_preamble(Mode::Pair, &[0; 16])).await.unwrap();
        let mut hs = Handshake::new(Pattern::Xx, true, &i.key, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hs, &pairing::commit_of(&[0xA1; 32], &i.public)).await.unwrap();
        handshake_receive(&*a, &mut hs).await.unwrap();
        let reveal = hs.write(&encode_hello(&id16(&i.device_id).unwrap(), &[0xA1; 32], &i.name).unwrap()).unwrap();
        a.send(reveal).await.unwrap();
        a.send(vec![7; 40]).await.unwrap(); // a record that does not open: the pairing ends and its close has nowhere to go
        assert_eq!(closed_at_the_grace(&mut task).await.unwrap().0, PairOutcome::Refused("closed".into()));
    }

    #[test]
    fn a_debug_print_of_an_outcome_names_no_id_name_or_key() {
        let peer = Peer { id: "ab".repeat(16), name: "Desk PC".into(), key: "cd".repeat(32), at: 1_700_000_000 };
        let text = format!("{:?} {:?}", PairOutcome::Paired(peer), PairOutcome::Declined { by_me: true });
        for secret in ["abab", "Desk PC", "cdcd", "1700"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
    }

    #[tokio::test]
    async fn a_frame_that_is_not_an_answer_ends_the_pairing() {
        // The responder is played by hand: after a real handshake it sends a transfer frame where a pairing answer belongs.
        let (i, r) = (identity(1, "A"), identity(2, "B"));
        let (clk, _) = clock();
        let (a, b) = MemoryEnd::pair();
        let side_i = side();
        let (_ih, ii) = pair_channel();
        let (i2, hooks) = (i.clone(), side_i.hooks.clone());
        let init = tokio::spawn(async move { run_initiator(a, &i2, [0xA1; 32], clk, Initiator::new(Ids::default()), &hooks, ii).await });
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let mut hs = Handshake::new(Pattern::Xx, false, &r.key, None, PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        let hello = encode_hello(&id16(&r.device_id).unwrap(), &[0xB1; 32], &r.name).unwrap();
        handshake_send(&*b, &mut hs, &hello).await.unwrap();
        decode_hello(&handshake_receive(&*b, &mut hs).await.unwrap()).unwrap();
        let channel = Channel::new(b.clone(), hs.finish().unwrap());
        channel.send_frame(&Frame::Accept { id: [3; 16] }).await.unwrap();
        assert_eq!(init.await.unwrap().0, PairOutcome::Refused("unexpected-frame".into()));
    }
}
