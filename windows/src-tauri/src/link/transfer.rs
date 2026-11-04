// One transfer conversation (docs/LINK-CONTRACT.md, "What each side does with each frame"), on either side. The rules are the pure machines of `flow.rs` (the connection rules included),
// run one event at a time; this file does the I/O around them: the preamble and the two `KK` handshake messages, the offer, the user's answer, the chunks to or from disk, progress, cancel,
// and the two minutes an offer may wait. Only a click on Accept accepts an offer (`ReceiveHandle::respond(true)` is called from that button alone): nothing in this file accepts for the user.
// The Mac's twin is LinkTransferRun.swift, with every fix of its reviews.
//
// A transfer runs only between paired machines: the sender knows the receiver's stored key, and the receiver looks up the sender's device id from the preamble and refuses one it does not know
// (the caller does that before it makes a run). Nothing here draws a random number except the transfer id the sender makes.
//
// Nothing waits for ever. A connection whose handshake is done must send its first frame within 10 s (a sender sends its offer right after the handshake) and nothing but a file coming in
// pushes that back; while a file comes in, a chunk must come within 60 s (the offer that waits for a click has its own 2 minutes); a sender whose offer nobody answers gives up after 130 s,
// and one whose bytes stop going out after 60 s. A sender's user may cancel at any time: its cancel frame is given 2 s like every frame, and a cancel that comes while the handshake is still
// going is waited for 2 s too, then the connection is cut (the conversation reads nothing before its offer is out). A frame this side sends is given 2 s (`Channel::send_best_effort`), then
// the connection is cut, so a peer that stopped reading cannot hold the conversation in a send. A conversation that is cut for that reason saves nothing. Each of those is a one-shot
// `IdleWatch` that exists only while its phase lasts, and each reader hands on at most `FrameWindow::FRAMES` frames the conversation has not taken yet. A peer gets one decline per connection
// (a sender makes a connection for each file): the second ends the connection.
//
// The disk is written from the conversation's own task: a chunk is at most 32 KiB, and a write of that size is not worth a thread of its own.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};

use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio::time::Duration;

use super::bytes::{hex, id16, key32};
use super::channel::{close_within, handshake_receive, handshake_send, Channel, FrameWindow, IdleWatch, LinkError, Transport};
use super::files::{Sink, Source};
use super::flow::{self, Abort, ConnEvent, Conn, Event, Notify, RState, SEvent, SState, User};
use super::frames::{encode_preamble, Frame, Mode, CHUNK_SIZE, DECLINE_USER, plan_chunks};
use super::identity::{Identity, Peer};
use super::noise::{Handshake, Pattern, PROLOGUE};
use super::pairing::OFFER_TIMEOUT_MS;

#[derive(Clone, PartialEq, Eq)]
pub enum TransferOutcome {
    /// The received file's path; None on the sending side.
    Completed(Option<PathBuf>),
    /// The receiver said no (sender), or this side's own decline (receiver: reason 0).
    Declined { reason: u8 },
    /// Nobody answered the offer in 2 minutes.
    Expired,
    /// Either user cancelled during the transfer, or the other side did.
    Cancelled,
    /// The sender withdrew an offer that was waiting.
    Withdrawn,
    /// A rule or the wire ended it: a `flow::Abort` word, or "closed", "handshake", "disk", "idle", "stalled", "busy".
    Aborted(String),
}

impl std::fmt::Debug for TransferOutcome {
    /// The kind of ending and its fixed word: the received file's path is never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransferOutcome::Completed(_) => f.debug_struct("Completed").finish_non_exhaustive(),
            TransferOutcome::Declined { reason } => f.debug_struct("Declined").field("reason", reason).finish(),
            TransferOutcome::Expired => f.write_str("Expired"),
            TransferOutcome::Cancelled => f.write_str("Cancelled"),
            TransferOutcome::Withdrawn => f.write_str("Withdrawn"),
            TransferOutcome::Aborted(word) => f.debug_tuple("Aborted").field(word).finish(),
        }
    }
}

/// What the Accept card shows. `name` is the **sanitized** name, the one that will be saved.
#[derive(Clone, PartialEq, Eq)]
pub struct Offer {
    pub transfer_id: String,
    pub name: String,
    pub size: u64,
    pub peer_id: String,
    pub peer_name: String,
}

impl std::fmt::Debug for Offer {
    /// A fixed label: the transfer id, the name, the size and the other machine's id and name are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Offer").finish_non_exhaustive()
    }
}

// ── Receiving ────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct ReceiveHooks {
    /// An offer is waiting for a click. Show the card.
    pub offered: Arc<dyn Fn(Offer) + Send + Sync>,
    pub progress: Arc<dyn Fn(u64, u64) + Send + Sync>,
    /// One active transfer for the whole machine (`Busy`), whichever peer it is from: false when another transfer is already claimed, or a card with buttons is on the island (the offer is then
    /// declined as busy). The argument says whose offer it is; it does not make the claim per machine.
    pub claim: Arc<dyn Fn(&str) -> bool + Send + Sync>,
    pub release: Arc<dyn Fn(&str) + Send + Sync>,
    /// The handshake is over; the connection no longer needs the listener's watchdog.
    pub handshake_done: Arc<dyn Fn() + Send + Sync>,
    /// Asked once, when the handshake is over and before anything is read: false closes the connection (too many connections are open already, `ConnectionCaps`). Nothing is shown for it.
    pub admit: Arc<dyn Fn() -> bool + Send + Sync>,
    /// false: the run does not give its claim back when it ends, its caller does (`ReceiveHandle::holds_claim`), once it has cleared what it keeps for the run. The early give-back of an offer
    /// this side refused itself is not affected.
    pub release_at_end: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct ReceiveTimings {
    /// The other side has this long for its two handshake messages after the preamble (the listener's own watchdog gives the same, the run does not rely on it).
    pub handshake_ms: u64,
    /// A connection that has finished its handshake must send its first frame within this long.
    pub first_frame_ms: u64,
    /// While a file comes in, the time the other side may take between two chunks.
    pub stall_ms: u64,
    /// A frame this side sends is waited for no longer than this.
    pub grace_ms: u64,
    pub offer_timeout_ms: u64,
}

impl Default for ReceiveTimings {
    fn default() -> ReceiveTimings {
        ReceiveTimings { handshake_ms: 10_000, first_frame_ms: flow::FIRST_FRAME_MS as u64, stall_ms: 60_000, grace_ms: 2_000, offer_timeout_ms: OFFER_TIMEOUT_MS as u64 }
    }
}

enum RxEvent {
    Frame(Frame),
    Closed,
    User(User),
    Timeout,
    Silent,
    Stalled,
}

/// What the service holds to answer an offer: the click, the cancel, and whether the run holds the machine's transfer place.
#[derive(Clone)]
pub struct ReceiveHandle {
    tx: mpsc::UnboundedSender<RxEvent>,
    holds: Arc<AtomicBool>,
}

impl ReceiveHandle {
    /// The user's click on Accept (true) or Decline (false).
    pub fn respond(&self, accept: bool) {
        let _ = self.tx.send(RxEvent::User(if accept { User::Accept } else { User::Decline }));
    }
    /// The user cancels the transfer that is running, or declines the offer that is waiting (the run turns a cancel that finds an offer waiting into a decline: the flow machine's cancel is for a
    /// transfer that runs, and an offer left to wait on would hold the machine's transfer place until its 2 minutes are over).
    pub fn cancel(&self) {
        let _ = self.tx.send(RxEvent::User(User::Cancel));
    }
    /// True from the moment this run's offer took the machine's one transfer place until it was given back. A caller that set `release_at_end` to false reads it after the run.
    pub fn holds_claim(&self) -> bool {
        self.holds.load(Ordering::SeqCst)
    }
}

pub struct ReceiveInbox {
    tx: mpsc::UnboundedSender<RxEvent>,
    rx: mpsc::UnboundedReceiver<RxEvent>,
    holds: Arc<AtomicBool>,
}

pub fn receive_channel() -> (ReceiveHandle, ReceiveInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    let holds = Arc::new(AtomicBool::new(false));
    (ReceiveHandle { tx: tx.clone(), holds: holds.clone() }, ReceiveInbox { tx, rx, holds })
}

/// What a run must stop when it returns, whichever way it returns.
struct Cleanup {
    reader: Option<JoinHandle<()>>,
    timer: Option<JoinHandle<()>>,
    watch: Option<IdleWatch>,
    window: FrameWindow,
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        if let Some(r) = &self.reader {
            r.abort();
        }
        if let Some(t) = &self.timer {
            t.abort();
        }
        if let Some(w) = &self.watch {
            w.stop();
        }
        self.window.close();
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Waiting {
    Nothing,
    FirstFrame,
    Chunk,
}

/// The end of a received file: `Sink::finish` does not look at the byte count, so it is checked here, against the size that was offered, before the file is made ordinary. A count that is not the
/// offer's (the machine already refuses a short `done` and an overflowing chunk, this is the second guard) leaves no file; the word is the machine's own (`short`, `overflow`). No sink is `disk`.
fn complete(sink: Option<&mut Sink>, total: u64) -> Result<PathBuf, &'static str> {
    let Some(s) = sink else { return Err("disk") };
    if s.written() != total {
        s.discard();
        return Err(if s.written() < total { "short" } else { "overflow" });
    }
    s.finish().map_err(|_| "disk")
}

/// The preamble was read already. Runs the `KK` handshake, then the conversation. `mark` is whether the file gets the mark of the web (Windows).
#[allow(clippy::too_many_arguments)]
pub async fn run_receive<T: Transport>(transport: Arc<T>, identity: &Identity, peer: &Peer, folder: PathBuf, mark: bool, hooks: &ReceiveHooks, timings: ReceiveTimings, inbox: ReceiveInbox) -> TransferOutcome {
    let ReceiveInbox { tx: post, mut rx, holds } = inbox;
    let mut sink: Option<Sink> = None;

    async fn end<T: Transport>(transport: &Arc<T>, hooks: &ReceiveHooks, peer: &Peer, holds: &AtomicBool, sink: &mut Option<Sink>, grace_ms: u64, outcome: TransferOutcome) -> TransferOutcome {
        if !matches!(outcome, TransferOutcome::Completed(_)) {
            if let Some(s) = sink.as_mut() {
                s.discard();
            }
        }
        if holds.load(Ordering::SeqCst) && hooks.release_at_end {
            holds.store(false, Ordering::SeqCst);
            (hooks.release)(&peer.id);
        }
        close_within(transport, grace_ms).await; // a close waits behind bytes a peer does not read
        outcome
    }
    macro_rules! finish {
        ($o:expr) => {
            return end(&transport, hooks, peer, &holds, &mut sink, timings.grace_ms, $o).await
        };
    }

    let channel = {
        let Some(remote) = key32(&peer.key) else { finish!(TransferOutcome::Aborted("handshake".into())) };
        let shake = {
            let t = transport.clone();
            IdleWatch::new(timings.handshake_ms, move || t.abort()) // a machine that sends its preamble and then says nothing does not hold this run
        };
        let shaken: Result<Channel<T>, LinkError> = async {
            let mut hs = Handshake::new(Pattern::Kk, false, &identity.key, Some(&remote), PROLOGUE, None)?;
            let first = handshake_receive(&*transport, &mut hs).await?;
            if !first.is_empty() {
                return Err(LinkError::Violation("kk payload".into())); // the KK payloads are empty (docs/LINK-CONTRACT.md); a port refuses a non-empty one
            }
            handshake_send(&*transport, &mut hs, &[]).await?;
            Ok(Channel::new(transport.clone(), hs.finish()?))
        }
        .await;
        shake.stop();
        match shaken {
            Ok(c) => Arc::new(c),
            Err(_) => finish!(TransferOutcome::Aborted("handshake".into())),
        }
    };
    if !(hooks.admit)() {
        finish!(TransferOutcome::Aborted("busy".into()));
    }
    (hooks.handshake_done)();

    let window = FrameWindow::new();
    let mut cleanup = Cleanup { reader: None, timer: None, watch: None, window: window.clone() };
    cleanup.reader = Some({
        let (channel, post, window) = (channel.clone(), post.clone(), window.clone());
        tokio::spawn(async move {
            loop {
                if !window.take().await {
                    return;
                }
                match channel.receive_frame().await {
                    Ok(f) => {
                        if post.send(RxEvent::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = post.send(RxEvent::Closed);
                        return;
                    }
                }
            }
        })
    });

    // What the connection is waited for: its first frame (while no offer is in hand), then a chunk at a time (while a file comes in). An offer that waits for the click has `timer`, not this.
    let mut waiting = Waiting::Nothing;
    macro_rules! wait_for {
        ($state:expr) => {{
            let want = match $state {
                RState::Idle => Waiting::FirstFrame,
                RState::Offered { .. } => Waiting::Nothing,
                RState::Receiving { .. } => Waiting::Chunk,
            };
            if want != waiting {
                if let Some(w) = cleanup.watch.take() {
                    w.stop();
                }
                waiting = want;
                // The watch cuts the connection itself, before it posts: the conversation may be stuck in a send and not read its queue until the cut fails that send.
                cleanup.watch = match want {
                    Waiting::Nothing => None,
                    Waiting::FirstFrame => {
                        let (t, p) = (transport.clone(), post.clone());
                        Some(IdleWatch::new(timings.first_frame_ms, move || { t.abort(); let _ = p.send(RxEvent::Silent); }))
                    }
                    Waiting::Chunk => {
                        let (t, p) = (transport.clone(), post.clone());
                        Some(IdleWatch::new(timings.stall_ms, move || { t.abort(); let _ = p.send(RxEvent::Stalled); }))
                    }
                };
            }
        }};
    }
    wait_for!(&RState::Idle);

    let mut conn = Conn { state: RState::Idle, declines: 0 };
    let (mut total, mut offered_name) = (0u64, String::new());
    while let Some(event) = rx.recv().await {
        let ev = match event {
            RxEvent::Closed => finish!(TransferOutcome::Aborted("closed".into())),
            // A report that was on its way when the connection moved on (an offer came in, a chunk did) is not for the phase it finds.
            RxEvent::Silent => {
                if waiting != Waiting::FirstFrame {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("idle".into()))
            }
            RxEvent::Stalled => {
                if waiting != Waiting::Chunk {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("stalled".into()))
            }
            RxEvent::Frame(f) => {
                window.give();
                // Only a chunk is activity: while a file comes in the limit is pushed back by chunks and by nothing else a peer sends (a cancel for another transfer, an offer), and while nothing
                // is going on the first-frame limit is not pushed back at all, so no stream of frames keeps a connection alive.
                if matches!(conn.state, RState::Receiving { .. }) && matches!(f, Frame::Chunk { .. }) {
                    if let Some(w) = &cleanup.watch {
                        w.touch();
                    }
                }
                Event::Frame(f)
            }
            RxEvent::User(User::Cancel) if matches!(conn.state, RState::Offered { .. }) => Event::User(User::Decline),
            RxEvent::User(u) => Event::User(u),
            RxEvent::Timeout => Event::Timeout,
        };
        // Busy across connections: the machine models this connection only. The machine has one transfer place (`hooks.claim`), whichever peer it is asked for.
        let is_offer = matches!(ev, Event::Frame(Frame::Offer { .. }));
        let mut granted = None;
        if is_offer && conn.state == RState::Idle && !holds.load(Ordering::SeqCst) {
            let ok = (hooks.claim)(&peer.id);
            if ok {
                holds.store(true, Ordering::SeqCst);
            }
            granted = Some(ok);
        }
        let out = flow::connection_step(&conn, &ConnEvent::Receiver { event: ev.clone(), granted });
        conn = out.conn.clone();
        for f in &out.send {
            channel.send_best_effort(f, timings.grace_ms).await;
        }
        if let Some(abort) = out.abort {
            // The second decline the machine makes on one connection is not answered: the connection is cut, so a peer that sends offers without end holds no place and churns no claim.
            if abort == Abort::Declines {
                transport.abort();
            }
            finish!(TransferOutcome::Aborted(abort.as_str().into()));
        }
        // The machine declined the offer itself (too large, a name it refuses): no card will come, so the machine's transfer place goes now, not when the connection closes.
        if holds.load(Ordering::SeqCst) && is_offer && conn.state == RState::Idle {
            holds.store(false, Ordering::SeqCst);
            (hooks.release)(&peer.id);
        }

        match out.notify {
            Some(Notify::Offer) => {
                if let RState::Offered { id, size, name } = &conn.state {
                    total = *size;
                    offered_name = name.clone();
                    if let Some(t) = cleanup.timer.take() {
                        t.abort();
                    }
                    let (p, ms) = (post.clone(), timings.offer_timeout_ms);
                    cleanup.timer = Some(tokio::spawn(async move {
                        tokio::time::sleep(Duration::from_millis(ms)).await;
                        let _ = p.send(RxEvent::Timeout);
                    }));
                    (hooks.offered)(Offer { transfer_id: hex(id), name: name.clone(), size: *size, peer_id: peer.id.clone(), peer_name: peer.name.clone() });
                }
            }
            Some(Notify::Expired) => finish!(TransferOutcome::Expired),
            Some(Notify::Withdrawn) => finish!(TransferOutcome::Withdrawn),
            Some(Notify::Cancelled) => finish!(TransferOutcome::Cancelled),
            Some(Notify::Complete) => match complete(sink.as_mut(), total) {
                Ok(path) => finish!(TransferOutcome::Completed(Some(path))),
                Err(why) => finish!(TransferOutcome::Aborted(why.into())),
            },
            _ => {}
        }

        wait_for!(&conn.state);

        // Effects of the new state.
        match (&ev, &conn.state) {
            (Event::User(User::Accept), RState::Receiving { id, .. }) => {
                if let Some(t) = cleanup.timer.take() {
                    t.abort();
                }
                // Only now is anything created on disk. A file that cannot be created ends the transfer with a cancel the other side sees.
                let mut s = Sink::new(folder.clone(), &offered_name, mark);
                match s.open() {
                    Ok(_) => sink = Some(s),
                    Err(_) => {
                        channel.send_best_effort(&Frame::Cancel { id: *id }, timings.grace_ms).await;
                        finish!(TransferOutcome::Aborted("disk".into()));
                    }
                }
            }
            (Event::Frame(Frame::Chunk { data, .. }), RState::Receiving { id, got, .. }) => {
                if sink.as_mut().map(|s| s.write(data)).transpose().is_err() {
                    channel.send_best_effort(&Frame::Cancel { id: *id }, timings.grace_ms).await;
                    finish!(TransferOutcome::Aborted("disk".into()));
                }
                (hooks.progress)(*got, total);
            }
            (Event::User(User::Decline), RState::Idle) => finish!(TransferOutcome::Declined { reason: DECLINE_USER }),
            _ => {}
        }
    }
    finish!(TransferOutcome::Aborted("closed".into()))
}

// ── Sending ──────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct SendHooks {
    pub progress: Arc<dyn Fn(u64, u64) + Send + Sync>,
}

#[derive(Debug, Clone, Copy)]
pub struct SendTimings {
    /// The other side has this long to answer the handshake (the listener gives a connection 10 s for it too).
    pub handshake_ms: u64,
    /// An offer nobody answers is given up after this long: a little more than the 2 minutes the receiver gives its user, so the receiver's own "did not answer in time" arrives first.
    pub accept_wait_ms: u64,
    /// While the file goes out, the longest the other side may take without letting one more chunk through.
    pub stall_ms: u64,
    /// A cancel is sent and not waited for longer than this: after it the connection is cut, however stuck it is.
    pub grace_ms: u64,
}

impl Default for SendTimings {
    fn default() -> SendTimings {
        SendTimings { handshake_ms: 10_000, accept_wait_ms: 130_000, stall_ms: 60_000, grace_ms: 2_000 }
    }
}

/// How the chunk pump ended: all sent (`done`), the file could not be read or changed size (`disk`, the file's fault), or a send failed (`lost`, the connection's fault).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pump {
    Done,
    Disk,
    Lost,
}

enum TxEvent {
    Frame(Frame),
    Closed,
    Cancel,
    Pumped(Pump),
    Unanswered,
    Stalled,
}

/// The deadline of a cancel that comes before the loop reads events (the handshake and the offer): armed by the cancel, ended when the offer is out (or the run is), and then it never fires.
struct HandshakeCut {
    state: StdMutex<(bool, Option<IdleWatch>)>,
}

impl HandshakeCut {
    fn arm(&self, runtime: &tokio::runtime::Handle, ms: u64, cut: impl FnOnce() + Send + 'static) {
        let mut g = self.state.lock().unwrap();
        if !g.0 && g.1.is_none() {
            g.1 = Some(IdleWatch::on(runtime, ms, cut));
        }
    }
    fn end(&self) {
        let mut g = self.state.lock().unwrap();
        g.0 = true;
        if let Some(w) = g.1.take() {
            w.stop();
        }
    }
}

#[derive(Clone)]
pub struct SendHandle {
    tx: mpsc::UnboundedSender<TxEvent>,
    cut: Arc<HandshakeCut>,
    runtime: tokio::runtime::Handle,
    abort: Arc<dyn Fn() + Send + Sync>,
    grace_ms: u64,
}

impl SendHandle {
    /// The user cancels: the run sends its cancel frame and ends, and the connection is cut only if that frame cannot go out within the grace, so the other side's user sees a cancel and not a
    /// connection that dropped. While the handshake is still going nothing is read (the cancel is read once the offer is out): the cancel is then given the grace for that to happen, and the
    /// connection is cut when it has not.
    pub fn cancel(&self) {
        let _ = self.tx.send(TxEvent::Cancel);
        let abort = self.abort.clone();
        self.cut.arm(&self.runtime, self.grace_ms, move || abort());
    }
}

pub struct SendInbox {
    tx: mpsc::UnboundedSender<TxEvent>,
    rx: mpsc::UnboundedReceiver<TxEvent>,
    cut: Arc<HandshakeCut>,
}

/// Made inside the runtime the run will use. `timings.grace_ms` must be the one the run gets.
pub fn send_channel<T: Transport>(transport: &Arc<T>, grace_ms: u64) -> (SendHandle, SendInbox) {
    let (tx, rx) = mpsc::unbounded_channel();
    let cut = Arc::new(HandshakeCut { state: StdMutex::new((false, None)) });
    let t = transport.clone();
    (SendHandle { tx: tx.clone(), cut: cut.clone(), runtime: tokio::runtime::Handle::current(), abort: Arc::new(move || t.abort()), grace_ms }, SendInbox { tx, rx, cut })
}

pub async fn run_send<T: Transport>(transport: Arc<T>, identity: &Identity, peer: &Peer, source: Source, hooks: &SendHooks, timings: SendTimings, inbox: SendInbox) -> TransferOutcome {
    let SendInbox { tx: post, mut rx, cut } = inbox;
    let source = Arc::new(StdMutex::new(source));
    macro_rules! finish {
        ($o:expr) => {{
            cut.end();
            source.lock().unwrap().close();
            close_within(&transport, timings.grace_ms).await;
            return $o;
        }};
    }
    // The handshake has a deadline of its own: a machine that accepts the connection and then says nothing does not hold the send for ever.
    let handshake = {
        let t = transport.clone();
        IdleWatch::new(timings.handshake_ms, move || t.abort())
    };
    let channel = {
        let (Some(remote), Some(me)) = (key32(&peer.key), id16(&identity.device_id)) else {
            handshake.stop();
            finish!(TransferOutcome::Aborted("handshake".into()))
        };
        let shaken: Result<Channel<T>, LinkError> = async {
            let mut hs = Handshake::new(Pattern::Kk, true, &identity.key, Some(&remote), PROLOGUE, None)?;
            transport.send(encode_preamble(Mode::Transfer, &me)).await?;
            handshake_send(&*transport, &mut hs, &[]).await?;
            let reply = handshake_receive(&*transport, &mut hs).await?;
            if !reply.is_empty() {
                return Err(LinkError::Violation("kk payload".into()));
            }
            Ok(Channel::new(transport.clone(), hs.finish()?))
        }
        .await;
        handshake.stop();
        match shaken {
            Ok(c) => Arc::new(c),
            Err(_) => finish!(TransferOutcome::Aborted("handshake".into())),
        }
    };

    let mut id = [0u8; 16];
    if getrandom::getrandom(&mut id).is_err() {
        finish!(TransferOutcome::Aborted("handshake".into()));
    }
    let (size, offer) = {
        let s = source.lock().unwrap();
        (s.size, Frame::Offer { id, size: s.size, name: s.name.clone(), kind: s.kind.clone() })
    };
    // The offer is a frame like the others: a peer that took the handshake and then stopped reading must not hold the send (and the file's handle) for ever.
    if channel.send_within(&offer, timings.grace_ms).await.is_err() {
        finish!(TransferOutcome::Aborted("closed".into()));
    }
    cut.end(); // from here the loop below reads a cancel and sends it as a frame

    let window = FrameWindow::new();
    let mut live = SendCleanup { reader: None, pump: None, wait: None, window: window.clone() };
    live.reader = Some({
        let (channel, post, window) = (channel.clone(), post.clone(), window.clone());
        tokio::spawn(async move {
            loop {
                if !window.take().await {
                    return;
                }
                match channel.receive_frame().await {
                    Ok(f) => {
                        if post.send(TxEvent::Frame(f)).is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = post.send(TxEvent::Closed);
                        return;
                    }
                }
            }
        })
    });
    // While the offer waits: the answer, within `accept_wait_ms`. While the file goes out: a chunk through within `stall_ms` (the pump touches it after each one).
    live.wait = Some({
        let p = post.clone();
        Arc::new(IdleWatch::new(timings.accept_wait_ms, move || {
            let _ = p.send(TxEvent::Unanswered);
        }))
    });

    let mut state = SState::Offered { id };
    while let Some(event) = rx.recv().await {
        let ev = match event {
            TxEvent::Closed => finish!(TransferOutcome::Aborted("closed".into())),
            TxEvent::Cancel => SEvent::UserCancel,
            TxEvent::Frame(f) => {
                window.give();
                SEvent::Frame(f)
            }
            TxEvent::Unanswered => {
                if !matches!(state, SState::Offered { .. }) {
                    continue; // it was on its way when the answer came
                }
                channel.send_best_effort(&Frame::Cancel { id }, timings.grace_ms).await;
                finish!(TransferOutcome::Expired)
            }
            TxEvent::Stalled => {
                if !matches!(state, SState::Sending { .. }) {
                    continue;
                }
                transport.abort();
                finish!(TransferOutcome::Aborted("stalled".into()))
            }
            TxEvent::Pumped(end) => match end {
                Pump::Done => finish!(TransferOutcome::Completed(None)),
                Pump::Disk => {
                    channel.send_best_effort(&Frame::Cancel { id }, timings.grace_ms).await;
                    finish!(TransferOutcome::Aborted("disk".into()))
                }
                Pump::Lost => finish!(TransferOutcome::Aborted("closed".into())),
            },
        };
        let decline_reason = if let SEvent::Frame(Frame::Decline { reason, .. }) = &ev { *reason } else { 0 };
        let was_offered = matches!(state, SState::Offered { .. });
        let user_cancel = matches!(ev, SEvent::UserCancel);
        let out = flow::sender_step(&state, &ev);
        state = out.state.clone();
        for f in &out.send {
            channel.send_best_effort(f, timings.grace_ms).await;
        }
        if let Some(abort) = out.abort {
            finish!(TransferOutcome::Aborted(abort.as_str().into()));
        }
        match out.notify {
            Some(Notify::Declined) => finish!(TransferOutcome::Declined { reason: decline_reason }),
            Some(Notify::Cancelled) => finish!(if was_offered && user_cancel { TransferOutcome::Withdrawn } else { TransferOutcome::Cancelled }),
            _ => {}
        }
        if was_offered && matches!(state, SState::Sending { .. }) {
            // Accepted: cut the file into chunks and send them, one at a time, each waiting for the transport. A file that is shorter or longer than it was when the offer went out is cancelled.
            // A read that fails or comes back short is the file's fault ("disk"); a send that fails is the connection's ("closed"). A pump that was cancelled posts nothing.
            let moving = {
                let p = post.clone();
                Arc::new(IdleWatch::new(timings.stall_ms, move || {
                    let _ = p.send(TxEvent::Stalled);
                }))
            };
            if let Some(w) = live.wait.replace(moving.clone()) {
                w.stop();
            }
            let (channel, source, post, hooks) = (channel.clone(), source.clone(), post.clone(), hooks.clone());
            live.pump = Some(tokio::spawn(async move {
                let end = |how: Pump| {
                    let _ = post.send(TxEvent::Pumped(how));
                };
                let mut sent = 0u64;
                for (offset, len) in plan_chunks(size, CHUNK_SIZE) {
                    let data = match source.lock().unwrap().read(len) {
                        Ok(d) if d.len() == len => d,
                        _ => return end(Pump::Disk),
                    };
                    if channel.send_frame(&Frame::Chunk { id, offset, data }).await.is_err() {
                        return end(Pump::Lost);
                    }
                    moving.touch();
                    sent += len as u64;
                    (hooks.progress)(sent, size);
                }
                let tail = source.lock().unwrap().read(1);
                if !matches!(tail, Ok(ref t) if t.is_empty()) {
                    return end(Pump::Disk);
                }
                if channel.send_frame(&Frame::Done { id }).await.is_err() {
                    return end(Pump::Lost);
                }
                end(Pump::Done)
            }));
        }
    }
    finish!(TransferOutcome::Aborted("closed".into()))
}

/// What a sending run must stop when it returns, whichever way it returns.
struct SendCleanup {
    reader: Option<JoinHandle<()>>,
    pump: Option<JoinHandle<()>>,
    wait: Option<Arc<IdleWatch>>,
    window: FrameWindow,
}

impl Drop for SendCleanup {
    fn drop(&mut self) {
        for h in [&self.reader, &self.pump].into_iter().flatten() {
            h.abort();
        }
        if let Some(w) = &self.wait {
            w.stop();
        }
        self.window.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::cards::Busy;
    use crate::link::channel::{MemoryEnd, StuckClose};
    use crate::link::frames::{decode_preamble, SIZE_MAX};
    use crate::link::noise::generate_static;
    use sha2::{Digest, Sha256};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::sync::Semaphore;

    fn temp(tag: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!("notchmeow-xfer-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn files_in(dir: &PathBuf) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(dir).map(|d| d.map(|e| e.unwrap().file_name().into_string().unwrap()).collect()).unwrap_or_default();
        v.sort();
        v
    }

    struct Pair {
        sender: Identity,
        receiver: Identity,
        /// The receiver as the sender knows it, and the sender as the receiver knows it.
        r_as_peer: Peer,
        s_as_peer: Peer,
    }

    fn pair() -> Pair {
        let mk = |tag: u8, name: &str| {
            let (key, public) = generate_static().unwrap();
            Identity { device_id: hex(&[tag; 16]), name: name.into(), key, public }
        };
        let (s, r) = (mk(1, "Sam's MacBook Pro"), mk(2, "Desk PC"));
        let r_as_peer = Peer { id: r.device_id.clone(), name: r.name.clone(), key: hex(&r.public), at: 0 };
        let s_as_peer = Peer { id: s.device_id.clone(), name: s.name.clone(), key: hex(&s.public), at: 0 };
        Pair { sender: s, receiver: r, r_as_peer, s_as_peer }
    }

    struct Seen {
        offers: Arc<StdMutex<Vec<Offer>>>,
        progress: Arc<StdMutex<Vec<(u64, u64)>>>,
        hooks: ReceiveHooks,
        busy: Arc<Busy>,
    }

    fn receive_hooks(busy: Arc<Busy>) -> Seen {
        let offers = Arc::new(StdMutex::new(Vec::new()));
        let progress = Arc::new(StdMutex::new(Vec::new()));
        let (o, p, b1, b2) = (offers.clone(), progress.clone(), busy.clone(), busy.clone());
        let hooks = ReceiveHooks {
            offered: Arc::new(move |offer| o.lock().unwrap().push(offer)),
            progress: Arc::new(move |g, t| p.lock().unwrap().push((g, t))),
            claim: Arc::new(move |id| b1.claim(id)),
            release: Arc::new(move |id| b2.release(id)),
            handshake_done: Arc::new(|| {}),
            admit: Arc::new(|| true),
            release_at_end: true,
        };
        Seen { offers, progress, hooks, busy }
    }

    fn spawn_receiver<T: Transport>(end: Arc<T>, p: &Pair, folder: PathBuf, seen: &Seen, timings: ReceiveTimings) -> (ReceiveHandle, JoinHandle<TransferOutcome>) {
        let (handle, inbox) = receive_channel();
        let (id, peer, hooks) = (p.receiver.clone(), p.s_as_peer.clone(), seen.hooks.clone());
        let task = tokio::spawn(async move {
            decode_preamble(&end.receive().await.unwrap()).unwrap(); // the listener reads the preamble first
            run_receive(end, &id, &peer, folder, false, &hooks, timings, inbox).await
        });
        (handle, task)
    }

    fn spawn_sender<T: Transport>(end: Arc<T>, p: &Pair, path: &std::path::Path, timings: SendTimings) -> (SendHandle, JoinHandle<TransferOutcome>, Arc<StdMutex<Vec<(u64, u64)>>>) {
        let (handle, inbox) = send_channel(&end, timings.grace_ms);
        let progress = Arc::new(StdMutex::new(Vec::new()));
        let pr = progress.clone();
        let (id, peer, path) = (p.sender.clone(), p.r_as_peer.clone(), path.to_path_buf());
        let task = tokio::spawn(async move {
            let source = Source::open(&path).unwrap();
            run_send(end, &id, &peer, source, &SendHooks { progress: Arc::new(move |s, t| pr.lock().unwrap().push((s, t))) }, timings, inbox).await
        });
        (handle, task, progress)
    }

    async fn until<F: Fn() -> bool>(what: &str, f: F) {
        for _ in 0..3000 {
            if f() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
        panic!("never happened: {what}");
    }

    /// A test that waits on a run ends by itself even when the run does not: an await that takes 20 real seconds is a failure, not a hang.
    async fn within<F: std::future::Future>(f: F) -> F::Output {
        tokio::time::timeout(Duration::from_secs(20), f).await.expect("took longer than 20 s")
    }

    fn sha(b: &[u8]) -> String {
        hex(&Sha256::digest(b))
    }

    fn write_file(dir: &PathBuf, name: &str, size: usize) -> (PathBuf, Vec<u8>) {
        let data: Vec<u8> = (0..size).map(|i| (i * 31 % 251) as u8).collect();
        let path = dir.join(name);
        std::fs::write(&path, &data).unwrap();
        (path, data)
    }

    #[tokio::test]
    async fn a_file_goes_over_in_chunks_after_a_click_and_arrives_whole() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, data) = write_file(&src_dir, "report.bin", 100_000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, sent) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer card", || !seen.offers.lock().unwrap().is_empty()).await;
        let offer = seen.offers.lock().unwrap()[0].clone();
        assert_eq!((offer.name.as_str(), offer.size, offer.peer_name.as_str()), ("report.bin", 100_000, "Sam's MacBook Pro"));
        assert!(files_in(&dest).is_empty(), "nothing is written before the click");
        rh.respond(true);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Completed(None));
        let got = match rtask.await.unwrap() {
            TransferOutcome::Completed(Some(path)) => path,
            other => panic!("{other:?}"),
        };
        assert_eq!(sha(&std::fs::read(&got).unwrap()), sha(&data));
        assert_eq!(files_in(&dest), vec!["report.bin"]);
        assert_eq!(*seen.progress.lock().unwrap().last().unwrap(), (100_000, 100_000));
        assert_eq!(sent.lock().unwrap().iter().map(|x| x.0).collect::<Vec<_>>(), vec![32768, 65536, 98304, 100_000]);
        assert!(!seen.busy.holds(&p.s_as_peer.id), "the place is given back");
    }

    #[tokio::test]
    async fn an_empty_file_is_a_transfer_with_no_chunks() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let path = src_dir.join("empty.txt");
        std::fs::write(&path, "").unwrap();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Completed(None));
        assert!(matches!(rtask.await.unwrap(), TransferOutcome::Completed(Some(_))));
        assert_eq!(std::fs::read(dest.join("empty.txt")).unwrap(), b"");
    }

    #[tokio::test]
    async fn a_click_on_decline_saves_nothing_and_the_sender_hears_no() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(false);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert!(files_in(&dest).is_empty());
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[tokio::test(start_paused = true)]
    async fn an_offer_nobody_answers_is_declined_after_two_minutes_and_creates_no_file() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, mut rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        tokio::time::sleep(Duration::from_millis(119_900)).await;
        assert!(!rtask.is_finished(), "alive just before the 2 minutes");
        tokio::time::sleep(Duration::from_millis(200)).await;
        let ended = tokio::time::timeout(Duration::from_millis(100), &mut rtask).await;
        assert_eq!(ended.expect("over within 100 ms of the 2 minutes").unwrap(), TransferOutcome::Expired);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Declined { reason: 1 });
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn a_sender_whose_offer_nobody_answers_gives_up_on_its_own_after_130_seconds() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let timings = ReceiveTimings { offer_timeout_ms: 10 * 60_000, ..ReceiveTimings::default() };
        let (_rh, _rtask) = spawn_receiver(b, &p, dest, &seen, timings);
        let (_sh, mut stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        tokio::time::sleep(Duration::from_millis(129_900)).await;
        assert!(!stask.is_finished(), "alive just before the 130 seconds");
        tokio::time::sleep(Duration::from_millis(200)).await;
        let ended = tokio::time::timeout(Duration::from_millis(100), &mut stask).await;
        assert_eq!(ended.expect("over within 100 ms of the 130 seconds").unwrap(), TransferOutcome::Expired);
    }

    /// A transport that lets the first `free` sends through and holds the rest until `open` is called: a connection that is slow, so a transfer can be stopped half way.
    struct Paced {
        inner: Arc<MemoryEnd>,
        left: Arc<Semaphore>,
    }

    impl Transport for Paced {
        async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
            self.left.acquire().await.map_err(|_| LinkError::Closed)?.forget();
            self.inner.send(record).await
        }
        async fn receive(&self) -> Result<Vec<u8>, LinkError> {
            self.inner.receive().await
        }
        async fn close(&self) {
            self.left.close();
            self.inner.close().await
        }
        fn abort(&self) {
            self.left.close();
            self.inner.abort()
        }
    }

    #[tokio::test]
    async fn the_receiver_cancels_in_the_middle_and_the_partial_file_is_gone() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "big.bin", 400_000);
        let (a, b) = MemoryEnd::pair();
        let left = Arc::new(Semaphore::new(3 + 2)); // the preamble, the handshake message, the offer, and two chunks
        let paced = Arc::new(Paced { inner: a, left: left.clone() });
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(paced, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        until("two chunks", || seen.progress.lock().unwrap().len() >= 2).await;
        assert_eq!(files_in(&dest), vec!["big.bin"], "the file exists while it comes in");
        rh.cancel();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Cancelled);
        assert_eq!(stask.await.unwrap(), TransferOutcome::Cancelled, "the sender sees a cancel, not a dropped connection");
        assert!(files_in(&dest).is_empty(), "nothing is left");
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[tokio::test]
    async fn the_sender_cancels_while_the_offer_waits_and_the_receiver_sees_it_withdrawn() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        sh.cancel();
        assert_eq!(stask.await.unwrap(), TransferOutcome::Withdrawn);
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Withdrawn);
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn a_second_transfer_while_one_runs_is_declined_as_busy_and_gets_no_card() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let busy = Arc::new(Busy::default());
        let (first, second) = (receive_hooks(busy.clone()), receive_hooks(busy.clone()));
        let (a1, b1) = MemoryEnd::pair();
        let (a2, b2) = MemoryEnd::pair();
        let (rh1, rtask1) = spawn_receiver(b1, &p, dest.clone(), &first, ReceiveTimings::default());
        let (_s1, stask1, _) = spawn_sender(a1, &p, &path, SendTimings::default());
        until("the first offer", || !first.offers.lock().unwrap().is_empty()).await;
        let (_rh2, rtask2) = spawn_receiver(b2, &p, dest.clone(), &second, ReceiveTimings::default());
        let (_s2, stask2, _) = spawn_sender(a2, &p, &path, SendTimings::default());
        assert_eq!(stask2.await.unwrap(), TransferOutcome::Declined { reason: 2 });
        assert!(second.offers.lock().unwrap().is_empty(), "no card for the second");
        let _ = rtask2.await;
        rh1.respond(true);
        assert_eq!(stask1.await.unwrap(), TransferOutcome::Completed(None));
        let _ = rtask1.await;
    }

    /// The sender played by hand over a real KK handshake, for the cases a real sender never produces.
    async fn manual_sender(end: Arc<MemoryEnd>, p: &Pair) -> Arc<Channel<MemoryEnd>> {
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &p.sender.key, Some(&remote), PROLOGUE, None).unwrap();
        end.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*end, &mut hs, &[]).await.unwrap();
        handshake_receive(&*end, &mut hs).await.unwrap();
        Arc::new(Channel::new(end, hs.finish().unwrap()))
    }

    fn offer(id: u8, size: u64, name: &str) -> Frame {
        Frame::Offer { id: [id; 16], size, name: name.into(), kind: String::new() }
    }

    #[tokio::test]
    async fn a_hostile_name_is_declined_as_not_acceptable_and_nothing_is_written() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "../../etc/passwd")).await.unwrap();
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Decline { id: [1; 16], reason: 4 });
        assert!(seen.offers.lock().unwrap().is_empty());
        assert!(!seen.busy.holds(&p.s_as_peer.id), "the place goes back at once when the machine declined the offer itself");
        // A valid offer after one machine-made decline still gets its card.
        ch.send_frame(&offer(2, 10, "ok.txt")).await.unwrap();
        until("the card", || !seen.offers.lock().unwrap().is_empty()).await;
        ch.send_frame(&Frame::Cancel { id: [2; 16] }).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Withdrawn);
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn the_second_machine_made_decline_on_a_connection_ends_it() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "../x")).await.unwrap();
        assert!(matches!(ch.receive_frame().await.unwrap(), Frame::Decline { reason: 4, .. }));
        ch.send_frame(&offer(2, 10, "../y")).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("declines".into()));
        assert!(ch.receive_frame().await.is_err(), "nothing was sent for the second, the connection is closed");
    }

    #[tokio::test]
    async fn a_file_over_4_gib_is_declined_as_too_large() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, _rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, SIZE_MAX + 1, "big.bin")).await.unwrap();
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Decline { id: [1; 16], reason: 3 });
        ch.send_frame(&offer(2, SIZE_MAX, "exactly.bin")).await.unwrap();
        until("4 GiB itself gets a card", || !seen.offers.lock().unwrap().is_empty()).await;
    }

    #[tokio::test(start_paused = true)]
    async fn a_connection_that_says_nothing_after_its_handshake_is_closed_after_10_seconds() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, mut rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let _ch = manual_sender(a, &p).await;
        tokio::time::sleep(Duration::from_millis(9_900)).await;
        assert!(!rtask.is_finished(), "alive just before the 10 seconds");
        tokio::time::sleep(Duration::from_millis(200)).await;
        let ended = tokio::time::timeout(Duration::from_millis(100), &mut rtask).await;
        assert_eq!(ended.expect("over within 100 ms of the 10 seconds").unwrap(), TransferOutcome::Aborted("idle".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn frames_that_are_not_an_offer_do_not_keep_a_silent_connection_alive() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        for _ in 0..8 {
            tokio::time::sleep(Duration::from_millis(1_000)).await;
            let _ = ch.send_frame(&Frame::Cancel { id: [9; 16] }).await; // a cancel for a transfer it does not know
        }
        tokio::time::sleep(Duration::from_millis(2_100)).await;
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("idle".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn a_sender_that_stops_sending_is_cut_after_60_seconds_and_the_partial_file_goes() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, mut rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 100, "slow.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(ch.receive_frame().await.unwrap(), Frame::Accept { id: [1; 16] });
        ch.send_frame(&Frame::Chunk { id: [1; 16], offset: 0, data: vec![7; 10] }).await.unwrap();
        tokio::time::sleep(Duration::from_millis(59_900)).await;
        assert!(!rtask.is_finished(), "alive just before the 60 seconds");
        tokio::time::sleep(Duration::from_millis(200)).await;
        let ended = tokio::time::timeout(Duration::from_millis(100), &mut rtask).await;
        assert_eq!(ended.expect("over within 100 ms of the 60 seconds").unwrap(), TransferOutcome::Aborted("stalled".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn only_a_chunk_pushes_the_stall_limit_back() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 100, "slow.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        ch.receive_frame().await.unwrap();
        // Every second a cancel for a transfer the connection does not know: harmless, and not a sign of life.
        for _ in 0..58 {
            tokio::time::sleep(Duration::from_millis(1_000)).await;
            ch.send_frame(&Frame::Cancel { id: [9; 16] }).await.unwrap();
        }
        tokio::time::sleep(Duration::from_millis(3_000)).await;
        tokio::task::yield_now().await;
        assert!(rtask.is_finished(), "cut 60 s after the accept: the cancels did not count as life");
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("stalled".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn done_before_every_byte_has_come_is_short_and_saves_nothing() {
        let p = pair();
        let dest = temp("dest");
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.send_frame(&offer(1, 10, "short.bin")).await.unwrap();
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        ch.receive_frame().await.unwrap();
        ch.send_frame(&Frame::Chunk { id: [1; 16], offset: 0, data: vec![1; 5] }).await.unwrap();
        ch.send_frame(&Frame::Done { id: [1; 16] }).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("short".into()));
        assert!(files_in(&dest).is_empty());
    }

    #[tokio::test]
    async fn a_chunk_out_of_order_or_past_the_size_ends_it() {
        for (frames, why) in [
            (vec![Frame::Chunk { id: [1; 16], offset: 5, data: vec![1; 5] }], "order"),
            (vec![Frame::Chunk { id: [1; 16], offset: 0, data: vec![1; 11] }], "overflow"),
            (vec![Frame::Chunk { id: [2; 16], offset: 0, data: vec![1; 5] }], "id"),
        ] {
            let p = pair();
            let dest = temp("dest");
            let (a, b) = MemoryEnd::pair();
            let seen = receive_hooks(Arc::new(Busy::default()));
            let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
            let ch = manual_sender(a, &p).await;
            ch.send_frame(&offer(1, 10, "x.bin")).await.unwrap();
            until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
            rh.respond(true);
            ch.receive_frame().await.unwrap();
            for f in &frames {
                ch.send_frame(f).await.unwrap();
            }
            assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted(why.into()), "{why}");
            assert!(files_in(&dest).is_empty(), "{why}");
        }
    }

    #[tokio::test]
    async fn a_machine_that_is_not_paired_under_this_key_cannot_complete_the_handshake() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        // A stranger who knows the sender's device id but holds another key.
        let (stranger, _) = generate_static().unwrap();
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &stranger, Some(&remote), PROLOGUE, None).unwrap();
        a.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*a, &mut hs, &[]).await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("handshake".into()));
        assert!(seen.offers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_kk_handshake_that_carries_a_payload_is_refused() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        let remote = key32(&p.r_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, true, &p.sender.key, Some(&remote), PROLOGUE, None).unwrap();
        a.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        handshake_send(&*a, &mut hs, b"smuggled").await.unwrap();
        assert_eq!(rtask.await.unwrap(), TransferOutcome::Aborted("handshake".into()));
    }

    #[tokio::test]
    async fn a_run_that_the_connection_caps_refuse_shows_nothing() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let mut hooks = seen.hooks.clone();
        hooks.admit = Arc::new(|| false);
        let (handle, inbox) = receive_channel();
        let (id, peer) = (p.receiver.clone(), p.s_as_peer.clone());
        let task = tokio::spawn(async move {
            decode_preamble(&b.receive().await.unwrap()).unwrap();
            run_receive(b, &id, &peer, temp("dest"), false, &hooks, ReceiveTimings::default(), inbox).await
        });
        let _ch = manual_sender(a, &p).await;
        assert_eq!(task.await.unwrap(), TransferOutcome::Aborted("busy".into()));
        assert!(!handle.holds_claim() && seen.offers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_file_that_shrinks_while_it_is_sent_is_cancelled_by_the_sender() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "shrinks.bin", 80_000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (handle, inbox) = send_channel(&a, 2_000);
        let (id, peer) = (p.sender.clone(), p.r_as_peer.clone());
        let source = Source::open(&path).unwrap();
        std::fs::write(&path, vec![0u8; 10_000]).unwrap(); // the file is cut down after the offer's size was read; the open handle sees the new length on read
        let task = tokio::spawn(async move { run_send(a, &id, &peer, source, &SendHooks { progress: Arc::new(|_, _| {}) }, SendTimings::default(), inbox).await });
        let _ = handle;
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(task.await.unwrap(), TransferOutcome::Aborted("disk".into()));
        assert!(matches!(rtask.await.unwrap(), TransferOutcome::Cancelled));
        assert!(files_in(&dest).is_empty(), "a transfer never completes with fewer bytes than offered");
    }

    #[tokio::test]
    async fn a_cancel_that_finds_an_offer_waiting_declines_it_and_gives_the_place_back() {
        let p = pair();
        let (src_dir, dest) = (temp("src"), temp("dest"));
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.cancel(); // what closing the island or turning Visible off does to a run: the offer must not wait on for two minutes
        assert_eq!(within(rtask).await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert_eq!(within(stask).await.unwrap(), TransferOutcome::Declined { reason: 0 });
        assert!(files_in(&dest).is_empty());
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[test]
    fn a_transfer_is_complete_only_when_the_byte_count_is_the_offers() {
        let dest = temp("dest");
        let made = |name: &str, bytes: usize| {
            let mut s = Sink::new(dest.clone(), name, false);
            s.open().unwrap();
            s.write(&vec![1; bytes]).unwrap();
            s
        };
        let mut short = made("short.bin", 5);
        assert_eq!(complete(Some(&mut short), 10), Err("short"));
        let mut over = made("over.bin", 11);
        assert_eq!(complete(Some(&mut over), 10), Err("overflow"));
        assert!(files_in(&dest).is_empty(), "a count that is not the offer's leaves no file");
        let mut exact = made("exact.bin", 10);
        assert!(complete(Some(&mut exact), 10).is_ok());
        assert_eq!(files_in(&dest), vec!["exact.bin"]);
        assert_eq!(complete(None, 10), Err("disk"), "no sink, no file");
    }

    #[tokio::test]
    async fn a_folder_that_cannot_be_made_ends_the_transfer_and_the_sender_sees_a_cancel() {
        // The same branch as a drive that cannot hold the mark of the web (`SinkError::Mark`, Windows only): the sink does not open, nothing is kept, the other side hears a cancel.
        let p = pair();
        let (src_dir, tmp) = (temp("src"), temp("dest"));
        let blocker = tmp.join("not-a-folder");
        std::fs::write(&blocker, b"x").unwrap();
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (rh, rtask) = spawn_receiver(b, &p, blocker.clone(), &seen, ReceiveTimings::default());
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
        rh.respond(true);
        assert_eq!(within(rtask).await.unwrap(), TransferOutcome::Aborted("disk".into()));
        assert_eq!(within(stask).await.unwrap(), TransferOutcome::Cancelled);
        assert_eq!(std::fs::read(&blocker).unwrap(), b"x", "what was there is untouched");
        assert!(!seen.busy.holds(&p.s_as_peer.id));
    }

    #[tokio::test]
    async fn a_damaged_message_ends_the_receiver_and_nothing_is_sent_after_it() {
        for accepted in [false, true] {
            let p = pair();
            let dest = temp("dest");
            let (a, b) = MemoryEnd::pair();
            let seen = receive_hooks(Arc::new(Busy::default()));
            let (rh, rtask) = spawn_receiver(b, &p, dest.clone(), &seen, ReceiveTimings::default());
            let ch = manual_sender(a, &p).await;
            ch.send_frame(&offer(1, 10, "x.bin")).await.unwrap();
            until("the offer", || !seen.offers.lock().unwrap().is_empty()).await;
            if accepted {
                rh.respond(true);
                assert_eq!(ch.receive_frame().await.unwrap(), Frame::Accept { id: [1; 16] });
                ch.send_frame(&Frame::Chunk { id: [1; 16], offset: 0, data: vec![1; 5] }).await.unwrap();
                until("the chunk", || !seen.progress.lock().unwrap().is_empty()).await;
                assert_eq!(files_in(&dest), vec!["x.bin"]);
            }
            ch.transport().send(vec![7; 40]).await.unwrap(); // a record that does not open
            assert_eq!(within(rtask).await.unwrap(), TransferOutcome::Aborted("closed".into()), "accepted: {accepted}");
            assert_eq!(within(ch.transport().receive()).await.unwrap_err(), LinkError::Closed, "nothing came back after the damage (accepted: {accepted})");
            assert!(files_in(&dest).is_empty(), "accepted: {accepted}");
            assert!(!seen.busy.holds(&p.s_as_peer.id));
        }
    }

    #[tokio::test]
    async fn a_damaged_message_ends_the_sender_and_nothing_is_sent_after_it() {
        let p = pair();
        let src_dir = temp("src");
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let (_sh, stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        // The receiver, played by hand over a real KK handshake.
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let remote = key32(&p.s_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, false, &p.receiver.key, Some(&remote), PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        handshake_send(&*b, &mut hs, &[]).await.unwrap();
        let ch = Channel::new(b.clone(), hs.finish().unwrap());
        assert!(matches!(ch.receive_frame().await.unwrap(), Frame::Offer { .. }));
        b.send(vec![7; 40]).await.unwrap(); // a record that does not open
        assert_eq!(within(stask).await.unwrap(), TransferOutcome::Aborted("closed".into()));
        assert_eq!(within(b.receive()).await.unwrap_err(), LinkError::Closed, "no cancel and no other frame went out after the damage");
    }

    /// A tight look at a limit: alive just before it, over within 100 ms after it (paused time).
    async fn ends_between<R: std::fmt::Debug>(task: &mut JoinHandle<R>, limit_ms: u64) -> R {
        tokio::time::sleep(Duration::from_millis(limit_ms - 100)).await;
        assert!(!task.is_finished(), "alive 100 ms before {limit_ms} ms");
        tokio::time::sleep(Duration::from_millis(200)).await;
        tokio::time::timeout(Duration::from_millis(100), task).await.unwrap_or_else(|_| panic!("not over within 100 ms of {limit_ms} ms")).unwrap()
    }

    #[tokio::test(start_paused = true)]
    async fn a_peer_that_sends_its_preamble_and_then_says_nothing_ends_the_receiver_at_10_seconds() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, mut rtask) = spawn_receiver(b, &p, temp("dest"), &seen, ReceiveTimings::default());
        a.send(encode_preamble(Mode::Transfer, &id16(&p.sender.device_id).unwrap())).await.unwrap();
        assert_eq!(ends_between(&mut rtask, 10_000).await, TransferOutcome::Aborted("handshake".into()));
        assert_eq!(within(a.receive()).await.unwrap_err(), LinkError::Closed, "nothing was sent");
        assert!(seen.offers.lock().unwrap().is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn a_machine_that_takes_the_connection_and_says_nothing_ends_the_sender_at_10_seconds() {
        let p = pair();
        let src_dir = temp("src");
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let (_sh, mut stask, _) = spawn_sender(a, &p, &path, SendTimings::default());
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        b.receive().await.unwrap(); // the first handshake message, and then nothing
        assert_eq!(ends_between(&mut stask, 10_000).await, TransferOutcome::Aborted("handshake".into()));
        assert_eq!(within(b.receive()).await.unwrap_err(), LinkError::Closed, "nothing else was sent");
    }

    #[tokio::test(start_paused = true)]
    async fn a_peer_that_never_reads_the_offer_ends_the_sender_within_the_grace_and_nothing_else_goes_out() {
        let p = pair();
        let src_dir = temp("src");
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let paced = Arc::new(Paced { inner: a, left: Arc::new(Semaphore::new(2)) }); // the preamble and the handshake message go, the offer does not
        let (_sh, mut stask, _) = spawn_sender(paced, &p, &path, SendTimings::default());
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let remote = key32(&p.s_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, false, &p.receiver.key, Some(&remote), PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        handshake_send(&*b, &mut hs, &[]).await.unwrap();
        // The receiver stops here: it reads nothing more.
        assert_eq!(ends_between(&mut stask, 2_000).await, TransferOutcome::Aborted("closed".into()));
        assert_eq!(within(b.receive()).await.unwrap_err(), LinkError::Closed, "the offer never left");
    }

    #[tokio::test(start_paused = true)]
    async fn a_close_that_waits_behind_a_peer_that_stopped_reading_does_not_hold_the_sender() {
        let p = pair();
        let src_dir = temp("src");
        let (path, _) = write_file(&src_dir, "a.bin", 1000);
        let (a, b) = MemoryEnd::pair();
        let stuck = StuckClose::new(a);
        let (_sh, mut stask, _) = spawn_sender(stuck, &p, &path, SendTimings::default());
        decode_preamble(&b.receive().await.unwrap()).unwrap();
        let remote = key32(&p.s_as_peer.key).unwrap();
        let mut hs = Handshake::new(Pattern::Kk, false, &p.receiver.key, Some(&remote), PROLOGUE, None).unwrap();
        handshake_receive(&*b, &mut hs).await.unwrap();
        handshake_send(&*b, &mut hs, &[]).await.unwrap();
        let ch = Channel::new(b.clone(), hs.finish().unwrap());
        assert!(matches!(ch.receive_frame().await.unwrap(), Frame::Offer { .. }));
        b.send(vec![7; 40]).await.unwrap(); // a record that does not open: the run ends, and its close has nowhere to go
        assert_eq!(ends_between(&mut stask, 2_000).await, TransferOutcome::Aborted("closed".into()));
    }

    #[tokio::test(start_paused = true)]
    async fn a_close_that_waits_behind_a_peer_that_stopped_reading_does_not_hold_the_receiver() {
        let p = pair();
        let (a, b) = MemoryEnd::pair();
        let stuck = StuckClose::new(b);
        let seen = receive_hooks(Arc::new(Busy::default()));
        let (_rh, mut rtask) = spawn_receiver(stuck, &p, temp("dest"), &seen, ReceiveTimings::default());
        let ch = manual_sender(a, &p).await;
        ch.transport().send(vec![7; 40]).await.unwrap(); // a record that does not open
        assert_eq!(ends_between(&mut rtask, 2_000).await, TransferOutcome::Aborted("closed".into()));
    }

    #[test]
    fn a_debug_print_names_no_path_id_or_name() {
        let offer = Offer { transfer_id: "ab".repeat(16), name: "secret-plan.pdf".into(), size: 4_242, peer_id: "cd".repeat(16), peer_name: "Sam's MacBook Pro".into() };
        let done = TransferOutcome::Completed(Some(PathBuf::from("/home/sam/Downloads/NotchMeow/secret-plan.pdf")));
        let text = format!("{offer:?} {done:?} {:?} {:?}", TransferOutcome::Declined { reason: 2 }, TransferOutcome::Aborted("disk".into()));
        for secret in ["abab", "cdcd", "secret-plan", "Sam", "/home", "Downloads", "4242"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        assert!(text.contains("Completed") && text.contains("reason: 2") && text.contains("disk"), "{text}");
    }

    #[test]
    fn the_default_watches_are_the_macs_and_the_reviews_numbers() {
        let r = ReceiveTimings::default();
        assert_eq!((r.handshake_ms, r.first_frame_ms, r.stall_ms, r.grace_ms, r.offer_timeout_ms), (10_000, 10_000, 60_000, 2_000, 120_000));
        let s = SendTimings::default();
        assert_eq!((s.handshake_ms, s.accept_wait_ms, s.stall_ms, s.grace_ms), (10_000, 130_000, 60_000, 2_000));
    }
}
