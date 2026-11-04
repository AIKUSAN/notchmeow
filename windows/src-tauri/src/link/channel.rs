// The link's connection layer (sub-project G2): a transport that carries whole records, and the channel that puts Noise transport messages and frames on it, with the small helpers every
// conversation uses to make sure nothing waits for ever. No socket in this file: the real transport (`net.rs`) cuts a TCP stream into records, and the tests use `MemoryEnd`. The Mac's
// twin is LinkChannel.swift.

use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};

use tokio::sync::{Mutex, Semaphore};
#[cfg(test)]
use tokio::sync::{mpsc, Notify};
use tokio::time::{Duration, Instant};

use super::frames::{self, Frame, FrameError, NOISE_MAX};
use super::noise::{Handshake, NoiseError, Transport as NoiseTransport};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkError {
    Closed,
    /// The other side broke the protocol, or a message did not open.
    Violation(String),
    /// A fixed sentence about the socket, never an address, a name or a path.
    Io(String),
}

impl std::fmt::Display for LinkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LinkError::Closed => f.write_str("closed"),
            LinkError::Violation(s) => write!(f, "violation: {s}"),
            LinkError::Io(s) => write!(f, "io: {s}"),
        }
    }
}

impl std::error::Error for LinkError {}

impl From<NoiseError> for LinkError {
    fn from(e: NoiseError) -> LinkError {
        LinkError::Violation(format!("noise {e}"))
    }
}

impl From<FrameError> for LinkError {
    fn from(e: FrameError) -> LinkError {
        LinkError::Violation(format!("frame {e}"))
    }
}

/// Carries whole records (one record is one Noise message, or the preamble): `send` takes a record's bytes, 1 to 65535 of them, and `receive` gives the bytes of the next whole record without the
/// length prefix that the wire puts in front (`frames::encode_record`, which the real transport applies). `receive` fails when the other end has closed.
pub trait Transport: Send + Sync + 'static {
    fn send(&self, record: Vec<u8>) -> impl Future<Output = Result<(), LinkError>> + Send;
    fn receive(&self) -> impl Future<Output = Result<Vec<u8>, LinkError>> + Send;
    /// Flushes what was sent and closes. Calling it twice is harmless.
    fn close(&self) -> impl Future<Output = ()> + Send;
    /// Hard stop, from any task: nothing is flushed, and a send or a read that is pending fails at once. For a peer that stopped reading (a `close` would wait behind its stalled bytes).
    fn abort(&self);
}

/// A one-shot deadline that activity pushes back: it fires `fire` once, `ms` milliseconds after the last `touch` (or after it was made), and then it is over. It never polls: it sleeps for
/// the time that is left, wakes once, and either fires or sleeps for what is left again. Made when something is pending, stopped when it is not (`stop`, or by being dropped), so nothing
/// sleeps for a conversation that ended. Must be made inside a tokio runtime.
pub struct IdleWatch {
    state: Arc<WatchState>,
    task: tokio::task::JoinHandle<()>,
}

struct WatchState {
    last: StdMutex<Instant>,
    over: AtomicBool,
}

impl IdleWatch {
    pub fn new(ms: u64, fire: impl FnOnce() + Send + 'static) -> IdleWatch {
        IdleWatch::on(&tokio::runtime::Handle::current(), ms, fire)
    }

    /// The same on a given runtime, for a caller that is not inside one (a click arriving from the window's own thread).
    pub fn on(runtime: &tokio::runtime::Handle, ms: u64, fire: impl FnOnce() + Send + 'static) -> IdleWatch {
        let state = Arc::new(WatchState { last: StdMutex::new(Instant::now()), over: AtomicBool::new(false) });
        let s = state.clone();
        let limit = Duration::from_millis(ms);
        let task = runtime.spawn(async move {
            loop {
                if s.over.load(Ordering::SeqCst) {
                    return;
                }
                let left = limit.saturating_sub(s.last.lock().unwrap().elapsed());
                if left.is_zero() {
                    if !s.over.swap(true, Ordering::SeqCst) {
                        fire();
                    }
                    return;
                }
                tokio::time::sleep(left).await;
            }
        });
        IdleWatch { state, task }
    }

    /// Something happened: the deadline moves.
    pub fn touch(&self) {
        *self.state.last.lock().unwrap() = Instant::now();
    }

    pub fn stop(&self) {
        self.state.over.store(true, Ordering::SeqCst);
        self.task.abort();
    }
}

impl Drop for IdleWatch {
    fn drop(&mut self) {
        self.stop();
    }
}

/// How many frames a reader may have handed on and not yet seen taken. The reader asks for a place (`take`) before it reads the next frame, and the conversation gives it back (`give`) when it
/// takes the frame from its queue, so a peer that sends faster than the conversation works leaves its bytes in the socket (where TCP slows it down), not in memory.
#[derive(Clone)]
pub struct FrameWindow {
    free: Arc<Semaphore>,
}

impl FrameWindow {
    pub const FRAMES: usize = 4;

    pub fn new() -> FrameWindow {
        FrameWindow { free: Arc::new(Semaphore::new(Self::FRAMES)) }
    }
    /// False when the conversation is over and the reader should stop.
    pub async fn take(&self) -> bool {
        match self.free.acquire().await {
            Ok(p) => {
                p.forget();
                true
            }
            Err(_) => false,
        }
    }
    pub fn give(&self) {
        self.free.add_permits(1);
    }
    /// The conversation is over: a reader that is waiting for a place is let go.
    pub fn close(&self) {
        self.free.close();
    }
}

impl Default for FrameWindow {
    fn default() -> FrameWindow {
        FrameWindow::new()
    }
}

/// Frames over an established Noise session. One sender at a time: a frame is encrypted and handed to the transport under a lock that is released in call order, so the nonces go out in the
/// order they were taken (a second sender waits for its turn, first come first served).
pub struct Channel<T: Transport> {
    transport: Arc<T>,
    noise: StdMutex<NoiseTransport>,
    send_turn: Mutex<()>,
}

impl<T: Transport> Channel<T> {
    pub fn new(transport: Arc<T>, noise: NoiseTransport) -> Channel<T> {
        Channel { transport, noise: StdMutex::new(noise), send_turn: Mutex::new(()) }
    }

    pub fn transport(&self) -> &Arc<T> {
        &self.transport
    }

    pub async fn send_frame(&self, frame: &Frame) -> Result<(), LinkError> {
        let _turn = self.send_turn.lock().await;
        let sealed = self.noise.lock().unwrap().encrypt(&frames::encode_frame(frame)?)?;
        self.transport.send(sealed).await
    }

    /// The next frame. A message that does not open, a frame that does not decode and a closed transport all end the conversation with an error.
    pub async fn receive_frame(&self) -> Result<Frame, LinkError> {
        let record = self.transport.receive().await?;
        let plain = self.noise.lock().unwrap().decrypt(&record)?;
        Ok(frames::decode_frame(&plain)?)
    }

    /// Sends one frame and waits for it no longer than `grace_ms`: the connection may be stuck behind bytes the peer does not read, and a conversation that waited for ever would hold everything it
    /// holds (a place among the connections, the transfer place). After the grace the transport is cut, which fails the stuck send and every read, and the conversation ends.
    pub async fn send_within(&self, frame: &Frame, grace_ms: u64) -> Result<(), LinkError> {
        let t = self.transport.clone();
        let cut = IdleWatch::new(grace_ms, move || t.abort());
        let sent = self.send_frame(frame).await;
        cut.stop();
        sent
    }

    /// `send_within` for a frame whose failure the conversation learns of anyway, from its reader.
    pub async fn send_best_effort(&self, frame: &Frame, grace_ms: u64) {
        let _ = self.send_within(frame, grace_ms).await;
    }
}

/// Handshake messages over a transport, one record each.
pub async fn handshake_send<T: Transport>(t: &T, hs: &mut Handshake, payload: &[u8]) -> Result<(), LinkError> {
    let message = hs.write(payload)?;
    if message.is_empty() || message.len() > NOISE_MAX {
        return Err(LinkError::Violation("handshake length".into()));
    }
    t.send(message).await
}

pub async fn handshake_receive<T: Transport>(t: &T, hs: &mut Handshake) -> Result<Vec<u8>, LinkError> {
    let message = t.receive().await?;
    Ok(hs.read(&message)?)
}

/// Closes a transport and waits for the close no longer than `grace_ms`: a close flushes, and a flush waits behind bytes a peer does not read. After the grace the close is given up and the
/// transport is aborted (which a real transport's pending close sees at once and ends), so the call returns whatever the transport does. Every conversation ends through this (or a path that
/// does the same), so a peer that stopped reading cannot hold a run, and what the run holds, for ever.
pub async fn close_within<T: Transport>(transport: &Arc<T>, grace_ms: u64) {
    if tokio::time::timeout(Duration::from_millis(grace_ms), transport.close()).await.is_err() {
        transport.abort();
    }
}

/// Two ends of an in-memory connection, for the tests (no sockets, no network). Records come out in the order they went in; after `close` the other end
/// reads what was already sent and then sees the end.
#[cfg(test)]
pub struct MemoryEnd {
    tx: StdMutex<Option<mpsc::UnboundedSender<Vec<u8>>>>,
    rx: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    closed: AtomicBool,
    cut: Notify,
}

#[cfg(test)]
impl MemoryEnd {
    pub fn pair() -> (Arc<MemoryEnd>, Arc<MemoryEnd>) {
        let (a_tx, b_rx) = mpsc::unbounded_channel();
        let (b_tx, a_rx) = mpsc::unbounded_channel();
        let end = |tx, rx| Arc::new(MemoryEnd { tx: StdMutex::new(Some(tx)), rx: Mutex::new(rx), closed: AtomicBool::new(false), cut: Notify::new() });
        (end(a_tx, a_rx), end(b_tx, b_rx))
    }

    fn shut(&self) {
        self.closed.store(true, Ordering::SeqCst);
        self.tx.lock().unwrap().take();
        self.cut.notify_waiters();
    }
}

#[cfg(test)]
impl Transport for MemoryEnd {
    async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
        if record.is_empty() || record.len() > NOISE_MAX {
            return Err(LinkError::Violation("record length".into())); // what the real transport's length prefix would refuse
        }
        if self.closed.load(Ordering::SeqCst) {
            return Err(LinkError::Closed);
        }
        match self.tx.lock().unwrap().as_ref() {
            Some(tx) => tx.send(record).map_err(|_| LinkError::Closed),
            None => Err(LinkError::Closed),
        }
    }

    async fn receive(&self) -> Result<Vec<u8>, LinkError> {
        let mut rx = self.rx.lock().await;
        loop {
            // Registered before the checks: an `abort` that comes between the checks and the wait must not be missed (`notify_waiters` wakes only the waiters that exist).
            let cut = self.cut.notified();
            tokio::pin!(cut);
            cut.as_mut().enable();
            if let Ok(record) = rx.try_recv() {
                return Ok(record);
            }
            if self.closed.load(Ordering::SeqCst) {
                return Err(LinkError::Closed);
            }
            tokio::select! {
                got = rx.recv() => return got.ok_or(LinkError::Closed),
                _ = cut => {}
            }
        }
    }

    async fn close(&self) {
        self.shut();
    }

    fn abort(&self) {
        self.shut();
    }
}

/// For the tests of the conversations: a transport whose `close` waits behind a peer that stopped reading, for ever, until `abort` is called (which every real transport honours). A test that
/// ends because the call returned has proved the cut, not the transport.
#[cfg(test)]
pub(crate) struct StuckClose {
    pub inner: Arc<MemoryEnd>,
    gate: Semaphore,
}

#[cfg(test)]
impl StuckClose {
    pub fn new(inner: Arc<MemoryEnd>) -> Arc<StuckClose> {
        Arc::new(StuckClose { inner, gate: Semaphore::new(0) })
    }
}

#[cfg(test)]
impl Transport for StuckClose {
    async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
        self.inner.send(record).await
    }
    async fn receive(&self) -> Result<Vec<u8>, LinkError> {
        self.inner.receive().await
    }
    async fn close(&self) {
        let _ = self.gate.acquire().await; // never granted: it ends only when `abort` closes the gate
        self.inner.close().await;
    }
    fn abort(&self) {
        self.gate.close();
        self.inner.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::noise::{generate_static, Pattern, PROLOGUE};
    use std::sync::atomic::AtomicUsize;

    /// A real XX handshake between two ends, so that frames travel encrypted.
    async fn session() -> (Channel<MemoryEnd>, Channel<MemoryEnd>) {
        let (a, b) = MemoryEnd::pair();
        let ((ka, _), (kb, _)) = (generate_static().unwrap(), generate_static().unwrap());
        let mut hi = Handshake::new(Pattern::Xx, true, &ka, None, PROLOGUE, None).unwrap();
        let mut hr = Handshake::new(Pattern::Xx, false, &kb, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        handshake_send(&*b, &mut hr, b"").await.unwrap();
        handshake_receive(&*a, &mut hi).await.unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        (Channel::new(a, hi.finish().unwrap()), Channel::new(b, hr.finish().unwrap()))
    }

    #[tokio::test]
    async fn frames_go_both_ways_in_order() {
        let (a, b) = session().await;
        let id = [7u8; 16];
        for n in 0..5u64 {
            a.send_frame(&Frame::Chunk { id, offset: n, data: vec![n as u8; 10] }).await.unwrap();
        }
        for n in 0..5u64 {
            assert_eq!(b.receive_frame().await.unwrap(), Frame::Chunk { id, offset: n, data: vec![n as u8; 10] });
        }
        b.send_frame(&Frame::Accept { id }).await.unwrap();
        assert_eq!(a.receive_frame().await.unwrap(), Frame::Accept { id });
    }

    #[tokio::test]
    async fn two_senders_at_once_keep_the_nonces_in_order() {
        let (a, b) = session().await;
        let a = Arc::new(a);
        let id = [1u8; 16];
        let tasks: Vec<_> = (0..20u64).map(|n| {
            let a = a.clone();
            tokio::spawn(async move { a.send_frame(&Frame::Chunk { id, offset: n, data: vec![1; 3] }).await })
        }).collect();
        for t in tasks {
            t.await.unwrap().unwrap();
        }
        for _ in 0..20 {
            b.receive_frame().await.unwrap(); // every message opens: none was sent out of the order it was sealed in
        }
    }

    #[tokio::test]
    async fn a_closed_end_reads_what_was_sent_and_then_the_end() {
        let (a, b) = MemoryEnd::pair();
        a.send(vec![1, 2, 3]).await.unwrap();
        a.close().await;
        assert_eq!(b.receive().await.unwrap(), vec![1, 2, 3]);
        assert_eq!(b.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(a.send(vec![1]).await.unwrap_err(), LinkError::Closed);
        assert_eq!(a.send(vec![]).await.unwrap_err(), LinkError::Violation("record length".into()));
    }

    #[tokio::test]
    async fn an_abort_fails_a_pending_read_at_once() {
        let (a, _b) = MemoryEnd::pair();
        let a2 = a.clone();
        let pending = tokio::spawn(async move { a2.receive().await });
        tokio::task::yield_now().await;
        a.abort();
        assert_eq!(pending.await.unwrap().unwrap_err(), LinkError::Closed);
    }

    #[tokio::test(start_paused = true)]
    async fn an_idle_watch_fires_once_after_its_time_and_a_touch_pushes_it_back() {
        let fired = Arc::new(AtomicUsize::new(0));
        let f = fired.clone();
        let watch = IdleWatch::new(1_000, move || { f.fetch_add(1, Ordering::SeqCst); });
        tokio::time::sleep(Duration::from_millis(900)).await;
        watch.touch();
        tokio::time::sleep(Duration::from_millis(900)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 0, "touched at 900 ms: not due at 1800 ms");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 1);
        tokio::time::sleep(Duration::from_secs(10)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 1, "once");
    }

    #[tokio::test(start_paused = true)]
    async fn a_stopped_or_dropped_watch_never_fires() {
        let fired = Arc::new(AtomicUsize::new(0));
        let f = fired.clone();
        let watch = IdleWatch::new(100, move || { f.fetch_add(1, Ordering::SeqCst); });
        watch.stop();
        let g = fired.clone();
        drop(IdleWatch::new(100, move || { g.fetch_add(1, Ordering::SeqCst); }));
        tokio::time::sleep(Duration::from_secs(5)).await;
        assert_eq!(fired.load(Ordering::SeqCst), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn a_send_that_the_peer_never_reads_is_cut_after_the_grace() {
        struct Stuck(Arc<AtomicBool>);
        impl Transport for Stuck {
            async fn send(&self, _r: Vec<u8>) -> Result<(), LinkError> {
                std::future::pending::<()>().await;
                Ok(())
            }
            async fn receive(&self) -> Result<Vec<u8>, LinkError> { Err(LinkError::Closed) }
            async fn close(&self) {}
            fn abort(&self) { self.0.store(true, Ordering::SeqCst); }
        }
        let cut = Arc::new(AtomicBool::new(false));
        let (ka, _) = generate_static().unwrap();
        let (kb, _) = generate_static().unwrap();
        // The handshake needs a working transport, so the noise state comes from a memory pair and the stuck transport carries only the frame.
        let (a, b) = MemoryEnd::pair();
        let mut hi = Handshake::new(Pattern::Xx, true, &ka, None, PROLOGUE, None).unwrap();
        let mut hr = Handshake::new(Pattern::Xx, false, &kb, None, PROLOGUE, None).unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        handshake_send(&*b, &mut hr, b"").await.unwrap();
        handshake_receive(&*a, &mut hi).await.unwrap();
        handshake_send(&*a, &mut hi, b"").await.unwrap();
        handshake_receive(&*b, &mut hr).await.unwrap();
        let channel = Arc::new(Channel::new(Arc::new(Stuck(cut.clone())), hi.finish().unwrap()));
        let c = channel.clone();
        let sending = tokio::spawn(async move { c.send_best_effort(&Frame::Cancel { id: [1; 16] }, 2_000).await });
        tokio::time::sleep(Duration::from_millis(1_900)).await;
        assert!(!cut.load(Ordering::SeqCst), "not yet");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(cut.load(Ordering::SeqCst), "cut after the 2 s grace");
        sending.abort();
    }

    #[tokio::test(start_paused = true)]
    async fn a_close_that_waits_behind_a_peer_that_stopped_reading_is_cut_after_the_grace() {
        let (a, _b) = MemoryEnd::pair();
        let stuck = StuckClose::new(a);
        let t = stuck.clone();
        let mut closing = tokio::spawn(async move { close_within(&t, 2_000).await });
        tokio::time::sleep(Duration::from_millis(1_900)).await;
        assert!(!closing.is_finished(), "not yet");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(tokio::time::timeout(Duration::from_millis(100), &mut closing).await.is_ok(), "ended by the cut at 2 s");
    }

    /// A transport whose `close` ignores `abort` and never returns: the worst a transport could do.
    struct DeafClose {
        aborted: AtomicBool,
    }

    impl Transport for DeafClose {
        async fn send(&self, _record: Vec<u8>) -> Result<(), LinkError> {
            Err(LinkError::Closed)
        }
        async fn receive(&self) -> Result<Vec<u8>, LinkError> {
            Err(LinkError::Closed)
        }
        async fn close(&self) {
            std::future::pending::<()>().await;
        }
        fn abort(&self) {
            self.aborted.store(true, Ordering::SeqCst);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn close_within_does_not_depend_on_the_transport_honouring_the_abort() {
        let t = Arc::new(DeafClose { aborted: AtomicBool::new(false) });
        let t2 = t.clone();
        let mut closing = tokio::spawn(async move { close_within(&t2, 2_000).await });
        tokio::time::sleep(Duration::from_millis(1_900)).await;
        assert!(!closing.is_finished(), "not yet");
        assert!(!t.aborted.load(Ordering::SeqCst), "not aborted before the grace");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(tokio::time::timeout(Duration::from_millis(100), &mut closing).await.is_ok(), "the call ended at 2 s though the close never would");
        assert!(t.aborted.load(Ordering::SeqCst), "and the transport was aborted");
    }

    #[tokio::test]
    async fn the_frame_window_holds_a_fifth_frame_until_one_is_taken() {
        let w = FrameWindow::new();
        for _ in 0..FrameWindow::FRAMES {
            assert!(w.take().await);
        }
        let w2 = w.clone();
        let fifth = tokio::spawn(async move { w2.take().await });
        tokio::task::yield_now().await;
        assert!(!fifth.is_finished(), "the reader waits");
        w.give();
        assert!(fifth.await.unwrap());
        let w3 = w.clone();
        let waiting = tokio::spawn(async move { w3.take().await });
        tokio::task::yield_now().await;
        w.close();
        assert!(!waiting.await.unwrap(), "a closed window lets the reader go");
    }

    #[test]
    fn four_frames_may_wait_for_the_conversation() {
        assert_eq!(FrameWindow::FRAMES, 4);
    }
}
