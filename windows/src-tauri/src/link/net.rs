// The link on the network (sub-project G2): a transport over a TCP connection, and the listener that accepts connections. Everything here is event-driven: the listener waits on a socket and the
// connection reads wait on their sockets, and **nothing polls**. There is no listener until the service is told the machine is visible on the network (Settings → Devices, off by default).
// The Mac's twin is LinkNetwork.swift (the advert and the browser are `discovery.rs` here).
//
// Hardening that the contract does not need but a listener on a LAN does: a connection that has not finished its handshake in 10 seconds is cut, and no more than 8 connections wait at once
// for that (`MAX_PENDING`), 2 of them from one address (`MAX_PENDING_PER_SOURCE`; the address is a key in memory, never logged); records are cut by `frames::split_records` (a length of 0
// closes, a record is at most 65535 bytes, so the buffer stays small).

use std::collections::{HashMap, VecDeque};
use std::net::{IpAddr, Shutdown, SocketAddr};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Notify};
use tokio::task::JoinHandle;

use super::channel::{LinkError, Transport};
use super::frames::{encode_record, split_records};

struct ReadSide {
    half: OwnedReadHalf,
    buffer: Vec<u8>,
    queue: VecDeque<Vec<u8>>,
    ended: bool,
}

/// A TCP connection as a `Transport`: the bytes of the stream are cut into whole records on the way in and given a length on the way out. One reader at a time (the conversation's reader task).
pub struct TcpTransport {
    read: Mutex<ReadSide>,
    write: Mutex<Option<OwnedWriteHalf>>,
    /// A second handle on the same socket, so that `abort` can cut it from any thread: a `shutdown` fails a pending read and a pending write at once, even one stuck behind a peer that stopped reading.
    killer: std::net::TcpStream,
    aborted: AtomicBool,
    cut: Notify,
}

impl TcpTransport {
    pub fn new(stream: TcpStream) -> std::io::Result<Arc<TcpTransport>> {
        let std_stream = stream.into_std()?;
        let killer = std_stream.try_clone()?;
        std_stream.set_nonblocking(true)?;
        let stream = TcpStream::from_std(std_stream)?;
        let _ = stream.set_nodelay(true);
        let (half, write) = stream.into_split();
        Ok(Arc::new(TcpTransport { read: Mutex::new(ReadSide { half, buffer: Vec::new(), queue: VecDeque::new(), ended: false }), write: Mutex::new(Some(write)), killer, aborted: AtomicBool::new(false), cut: Notify::new() }))
    }

    /// Opens a connection and waits for it no longer than `timeout`.
    pub async fn connect(addr: SocketAddr, timeout: Duration) -> Result<Arc<TcpTransport>, LinkError> {
        let stream = tokio::time::timeout(timeout, TcpStream::connect(addr)).await.map_err(|_| LinkError::Io("connect timeout".into()))?.map_err(|e| LinkError::Io(e.kind().to_string()))?;
        TcpTransport::new(stream).map_err(|e| LinkError::Io(e.kind().to_string()))
    }

    /// The other end's address, as a key for the per-address cap. Never logged, never shown.
    pub fn peer_ip(&self) -> Option<IpAddr> {
        self.killer.peer_addr().ok().map(|a| a.ip())
    }
}

impl Transport for TcpTransport {
    async fn send(&self, record: Vec<u8>) -> Result<(), LinkError> {
        let framed = encode_record(&record).map_err(|_| LinkError::Violation("record length".into()))?;
        if self.aborted.load(Ordering::SeqCst) {
            return Err(LinkError::Closed);
        }
        let mut guard = self.write.lock().await;
        let Some(w) = guard.as_mut() else { return Err(LinkError::Closed) };
        tokio::select! {
            r = w.write_all(&framed) => r.map_err(|e| LinkError::Io(e.kind().to_string())),
            _ = self.cut.notified() => Err(LinkError::Closed),
        }
    }

    async fn receive(&self) -> Result<Vec<u8>, LinkError> {
        let mut side = self.read.lock().await;
        let mut chunk = vec![0u8; 65_537];
        loop {
            if let Some(r) = side.queue.pop_front() {
                return Ok(r);
            }
            if side.ended || self.aborted.load(Ordering::SeqCst) {
                return Err(LinkError::Closed);
            }
            let n = tokio::select! {
                n = side.half.read(&mut chunk) => n.unwrap_or(0),
                _ = self.cut.notified() => 0,
            };
            if n == 0 {
                side.ended = true;
                return Err(LinkError::Closed);
            }
            side.buffer.extend_from_slice(&chunk[..n]);
            match split_records(&side.buffer) {
                Ok((records, rest)) => {
                    side.buffer = rest;
                    side.queue.extend(records);
                }
                Err(_) => {
                    side.ended = true;
                    let _ = self.killer.shutdown(Shutdown::Both); // a record of length 0
                    return Err(LinkError::Violation("record".into()));
                }
            }
        }
    }

    /// Sends what is queued, tells the other side the stream is finished, and closes. A cut connection has nothing to flush.
    async fn close(&self) {
        if self.aborted.load(Ordering::SeqCst) {
            return;
        }
        if let Some(mut w) = self.write.lock().await.take() {
            let _ = tokio::select! { r = w.shutdown() => r, _ = self.cut.notified() => Ok(()) };
        }
        let _ = self.killer.shutdown(Shutdown::Both);
    }

    /// Hard stop: for a connection that is too slow. The pending reads and writes then fail and the conversation ends.
    fn abort(&self) {
        self.aborted.store(true, Ordering::SeqCst);
        let _ = self.killer.shutdown(Shutdown::Both);
        self.cut.notify_waiters();
    }
}

pub const MAX_PENDING: usize = 8;
pub const MAX_PENDING_PER_SOURCE: usize = 2;
pub const HANDSHAKE_SECONDS: u64 = 10;

/// A connection that has been accepted but has not finished its handshake. The service calls `finish()` when it has (or when it refuses the connection); until then a watchdog cuts the connection
/// `HANDSHAKE_SECONDS` after it was accepted, and the slot counts against `MAX_PENDING`.
#[derive(Clone)]
pub struct PendingSlot {
    inner: Arc<SlotInner>,
}

struct SlotInner {
    done: AtomicBool,
    release: StdMutex<Option<Box<dyn FnOnce() + Send>>>,
    watchdog: StdMutex<Option<JoinHandle<()>>>,
}

impl PendingSlot {
    pub fn is_finished(&self) -> bool {
        self.inner.done.load(Ordering::SeqCst)
    }

    /// Finishes the slot: its place is given back and its watchdog cancelled. True for the call that finished it, false for any later one (the service and the watchdog can arrive together; only the
    /// first one decides what happens to the connection).
    pub fn finish(&self) -> bool {
        if self.inner.done.swap(true, Ordering::SeqCst) {
            return false;
        }
        if let Some(w) = self.inner.watchdog.lock().unwrap().take() {
            w.abort();
        }
        if let Some(r) = self.inner.release.lock().unwrap().take() {
            r();
        }
        true
    }
}

#[derive(Default)]
struct Pending {
    total: usize,
    by_source: HashMap<IpAddr, usize>,
}

pub type OnConnection = Arc<dyn Fn(Arc<TcpTransport>, PendingSlot) + Send + Sync>;

/// The listener: accepts connections and hands each new one to the service. It exists only while the machine is visible on the network.
pub struct Listener {
    port: u16,
    stop: Arc<Notify>,
    stopped: Arc<AtomicBool>,
    task: JoinHandle<()>,
}

impl Listener {
    /// Starts listening. `bind` is `0.0.0.0:0` for the network (the system chooses the port) and `127.0.0.1:0` for the tests. IPv4 only: the advert is IPv4 only too (`discovery.rs`).
    pub async fn start(bind: SocketAddr, on_connection: OnConnection, handshake: Duration) -> std::io::Result<Listener> {
        let listener = TcpListener::bind(bind).await?;
        let port = listener.local_addr()?.port();
        let admit = Admit::new(on_connection, handshake);
        let (stop, stopped) = (Arc::new(Notify::new()), admit.stopped.clone());
        let s = stop.clone();
        let task = tokio::spawn(async move {
            loop {
                if admit.stopped.load(Ordering::SeqCst) {
                    return;
                }
                let accepted = tokio::select! {
                    a = listener.accept() => a,
                    _ = s.notified() => return,
                };
                let Ok((stream, from)) = accepted else {
                    tokio::time::sleep(Duration::from_millis(50)).await; // a transient accept error (descriptors): do not spin
                    continue;
                };
                admit.deliver(stream, from.ip());
            }
        });
        Ok(Listener { port, stop, stopped, task })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn stop(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        self.stop.notify_one();
        self.task.abort();
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop();
    }
}

/// What the accept loop needs to take in one accepted connection: the flag of a stopped listener, the pending counts, the handshake clock and the service's callback.
struct Admit {
    stopped: Arc<AtomicBool>,
    pending: Arc<StdMutex<Pending>>,
    handshake: Duration,
    on_connection: OnConnection,
}

impl Admit {
    fn new(on_connection: OnConnection, handshake: Duration) -> Admit {
        Admit { stopped: Arc::new(AtomicBool::new(false)), pending: Arc::new(StdMutex::new(Pending::default())), handshake, on_connection }
    }

    /// Takes in a connection that was just accepted: counts it against the caps (a ninth, or a third from one address, is closed without a byte), starts its handshake clock, and hands it to the
    /// service. `source` is a key in memory, never logged. The flag is read once more at the last moment: a connection accepted just as the listener was stopped, whose task runs late, is
    /// closed and never handed on, so a stopped listener never gives the service a connection.
    fn deliver(&self, stream: TcpStream, source: IpAddr) {
        let admitted = {
            let mut p = self.pending.lock().unwrap();
            if p.total >= MAX_PENDING || p.by_source.get(&source).copied().unwrap_or(0) >= MAX_PENDING_PER_SOURCE {
                false
            } else {
                p.total += 1;
                *p.by_source.entry(source).or_insert(0) += 1;
                true
            }
        };
        if !admitted {
            drop(stream);
            return;
        }
        let Ok(transport) = TcpTransport::new(stream) else {
            release(&self.pending, source);
            return;
        };
        let pend = self.pending.clone();
        let slot = PendingSlot { inner: Arc::new(SlotInner { done: AtomicBool::new(false), release: StdMutex::new(Some(Box::new(move || release(&pend, source)))), watchdog: StdMutex::new(None) }) };
        // The handshake clock starts at accept: the watchdog cuts the connection if the service has not finished the handshake in time.
        let (wslot, wt, handshake) = (slot.clone(), transport.clone(), self.handshake);
        let dog = tokio::spawn(async move {
            tokio::time::sleep(handshake).await;
            expire(&wslot, || wt.abort());
        });
        *slot.inner.watchdog.lock().unwrap() = Some(dog);
        if self.stopped.load(Ordering::SeqCst) {
            transport.abort();
            slot.finish();
            return;
        }
        (self.on_connection)(transport, slot);
    }
}

/// The handshake clock ran out: the slot is finished and the connection cut, unless the service finished the slot first (then the connection is the service's and is left alone).
fn expire(slot: &PendingSlot, cut: impl FnOnce()) {
    if slot.finish() {
        cut();
    }
}

fn release(pending: &Arc<StdMutex<Pending>>, source: IpAddr) {
    let mut p = pending.lock().unwrap();
    p.total = p.total.saturating_sub(1);
    if let Some(n) = p.by_source.get_mut(&source) {
        *n = n.saturating_sub(1);
        if *n == 0 {
            p.by_source.remove(&source);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    fn lo() -> SocketAddr {
        "127.0.0.1:0".parse().unwrap()
    }

    /// A listener on the loopback address that hands every connection to a channel, with its slot.
    async fn listen(handshake: Duration) -> (Listener, tokio::sync::mpsc::UnboundedReceiver<(Arc<TcpTransport>, PendingSlot)>) {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        let l = Listener::start(lo(), Arc::new(move |t, s| { let _ = tx.send((t, s)); }), handshake).await.unwrap();
        (l, rx)
    }

    #[tokio::test]
    async fn records_go_both_ways_over_real_tcp() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let client = TcpTransport::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port()), Duration::from_secs(5)).await.unwrap();
        let (server, slot) = rx.recv().await.unwrap();
        client.send(vec![1, 2, 3]).await.unwrap();
        client.send(vec![9; 65_535]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![1, 2, 3]);
        assert_eq!(server.receive().await.unwrap().len(), 65_535);
        server.send(vec![7; 100]).await.unwrap();
        assert_eq!(client.receive().await.unwrap(), vec![7; 100]);
        assert_eq!(client.send(vec![0; 65_536]).await.unwrap_err(), LinkError::Violation("record length".into()));
        assert_eq!(client.send(vec![]).await.unwrap_err(), LinkError::Violation("record length".into()));
        slot.finish();
        client.close().await;
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn a_record_of_length_zero_closes_the_connection() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let mut raw = TcpStream::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port())).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        raw.write_all(&[0, 0]).await.unwrap();
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Violation("record".into()));
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn two_records_in_one_segment_and_one_record_in_two_come_out_whole() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let mut raw = TcpStream::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port())).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        raw.write_all(&[0, 2, 0xAA, 0xBB, 0, 1, 0xCC, 0, 3, 1]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![0xAA, 0xBB]);
        assert_eq!(server.receive().await.unwrap(), vec![0xCC]);
        raw.write_all(&[2, 3]).await.unwrap();
        assert_eq!(server.receive().await.unwrap(), vec![1, 2, 3]);
    }

    #[tokio::test]
    async fn an_abort_cuts_a_pending_read_at_once_and_the_peer_sees_the_end() {
        let (l, mut rx) = listen(Duration::from_secs(10)).await;
        let client = TcpTransport::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port()), Duration::from_secs(5)).await.unwrap();
        let (server, _slot) = rx.recv().await.unwrap();
        let s2 = server.clone();
        let pending = tokio::spawn(async move { s2.receive().await });
        tokio::task::yield_now().await;
        server.abort();
        assert_eq!(pending.await.unwrap().unwrap_err(), LinkError::Closed);
        assert_eq!(client.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(server.send(vec![1]).await.unwrap_err(), LinkError::Closed);
    }

    // Real time and a short handshake: a paused clock would run a connect's own timeout out before the socket answered.
    #[tokio::test]
    async fn a_connection_that_does_not_finish_its_handshake_in_time_is_cut_and_its_place_freed() {
        let (l, mut rx) = listen(Duration::from_millis(300)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        let silent = TcpTransport::connect(addr, Duration::from_secs(5)).await.unwrap();
        let (server, slot) = rx.recv().await.unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!slot.is_finished());
        tokio::time::sleep(Duration::from_millis(400)).await;
        assert!(slot.is_finished(), "the watchdog fired");
        assert_eq!(server.receive().await.unwrap_err(), LinkError::Closed);
        assert_eq!(silent.receive().await.unwrap_err(), LinkError::Closed);
    }

    #[tokio::test]
    async fn at_most_two_connections_wait_from_one_address() {
        let (l, mut rx) = listen(Duration::from_secs(60)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        let mut clients = vec![];
        for _ in 0..4 {
            clients.push(TcpStream::connect(addr).await.unwrap());
        }
        let got = Arc::new(AtomicUsize::new(0));
        let mut slots = vec![];
        while let Ok(Some(x)) = tokio::time::timeout(Duration::from_millis(300), rx.recv()).await {
            got.fetch_add(1, Ordering::SeqCst);
            slots.push(x);
        }
        assert_eq!(got.load(Ordering::SeqCst), 2, "the third and fourth connection from this address were dropped at once");
        slots.remove(0).1.finish();
        let _again = TcpStream::connect(addr).await.unwrap();
        let next = tokio::time::timeout(Duration::from_secs(2), rx.recv()).await.unwrap();
        assert!(next.is_some(), "a place that was freed is used again");
        drop(clients);
    }

    #[tokio::test]
    async fn a_stopped_listener_accepts_nothing() {
        let (l, _rx) = listen(Duration::from_secs(10)).await;
        let addr = SocketAddr::new("127.0.0.1".parse().unwrap(), l.port());
        l.stop();
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(TcpStream::connect(addr).await.is_err(), "nothing listens");
    }

    /// A bounded wait for a test step, so that a test that goes wrong fails instead of hanging.
    async fn within<F: std::future::Future>(f: F) -> F::Output {
        tokio::time::timeout(Duration::from_secs(10), f).await.expect("ended by itself")
    }

    /// A server-side transport with a sender that is stuck: the peer is a raw socket that never reads, and a task sends records until the kernel's buffers are full. Real time and real sockets.
    async fn stuck() -> (Listener, TcpStream, Arc<TcpTransport>, JoinHandle<LinkError>) {
        let (l, mut rx) = listen(Duration::from_secs(60)).await;
        let peer = TcpStream::connect(SocketAddr::new("127.0.0.1".parse().unwrap(), l.port())).await.unwrap();
        let (server, slot) = rx.recv().await.unwrap();
        slot.finish();
        let sent = Arc::new(AtomicUsize::new(0));
        let (s, n) = (server.clone(), sent.clone());
        let sender = tokio::spawn(async move {
            loop {
                if let Err(e) = s.send(vec![0; 65_535]).await {
                    return e;
                }
                n.fetch_add(1, Ordering::SeqCst);
            }
        });
        // Stuck: the count of records that went out has stopped moving.
        let mut last = usize::MAX;
        within(async {
            loop {
                let now = sent.load(Ordering::SeqCst);
                if now > 0 && now == last {
                    break;
                }
                last = now;
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await;
        (l, peer, server, sender)
    }

    // The conversations end through `close_within`, which can only be as good as the transport's `close`: after an abort it must return at once, even with a sender stuck behind a peer that never reads.
    #[tokio::test]
    async fn a_close_that_waits_behind_a_stuck_send_returns_as_soon_as_the_connection_is_aborted() {
        let (_l, _peer, server, sender) = stuck().await;
        let s = server.clone();
        let closing = tokio::spawn(async move { s.close().await });
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!closing.is_finished(), "the close waits behind the stuck send");
        server.abort();
        within(closing).await.unwrap();
        assert!(matches!(within(sender).await.unwrap(), LinkError::Closed | LinkError::Io(_)), "the stuck send failed");
    }

    #[tokio::test]
    async fn close_within_ends_after_its_grace_when_the_peer_never_reads_and_leaves_the_connection_cut() {
        let (_l, _peer, server, sender) = stuck().await;
        let began = std::time::Instant::now();
        within(crate::link::channel::close_within(&server, 300)).await;
        let took = began.elapsed();
        assert!(took >= Duration::from_millis(250), "it waited for the close, up to the grace ({took:?})");
        assert!(took < Duration::from_secs(5), "and no longer ({took:?})");
        assert_eq!(within(server.send(vec![1])).await.unwrap_err(), LinkError::Closed, "the connection was aborted");
        assert!(within(sender).await.is_ok());
    }

    // The accept loop checks the flag before it accepts, but a connection can be accepted just as the listener is stopped, and its task can run late: it is closed, never handed on.
    #[tokio::test]
    async fn a_connection_accepted_by_a_stopped_listener_is_closed_and_never_handed_on() {
        let raw = TcpListener::bind(lo()).await.unwrap();
        let mut client = TcpStream::connect(raw.local_addr().unwrap()).await.unwrap();
        let (stream, from) = raw.accept().await.unwrap();
        let handed = Arc::new(AtomicUsize::new(0));
        let h = handed.clone();
        let admit = Admit::new(Arc::new(move |_, _| { h.fetch_add(1, Ordering::SeqCst); }), Duration::from_secs(60));
        admit.stopped.store(true, Ordering::SeqCst);
        admit.deliver(stream, from.ip());
        assert_eq!(handed.load(Ordering::SeqCst), 0);
        assert_eq!(admit.pending.lock().unwrap().total, 0, "its place was given back");
        let mut byte = [0u8; 1];
        assert!(matches!(within(client.read(&mut byte)).await, Ok(0) | Err(_)), "the peer sees the end");
        // The same gate, not stopped, hands the next one on.
        let raw2 = TcpStream::connect(raw.local_addr().unwrap()).await.unwrap();
        let (stream2, from2) = raw.accept().await.unwrap();
        admit.stopped.store(false, Ordering::SeqCst);
        admit.deliver(stream2, from2.ip());
        assert_eq!(handed.load(Ordering::SeqCst), 1);
        drop(raw2);
    }

    // The per-address test above can only come from one address (the loopback); the total cap is tried with made-up source addresses, through the same door the accept loop uses.
    #[tokio::test]
    async fn at_most_eight_connections_wait_in_all_whoever_they_come_from() {
        let raw = TcpListener::bind(lo()).await.unwrap();
        let addr = raw.local_addr().unwrap();
        let handed: Arc<StdMutex<Vec<(Arc<TcpTransport>, PendingSlot)>>> = Arc::new(StdMutex::new(Vec::new()));
        let h = handed.clone();
        let admit = Admit::new(Arc::new(move |t, s| h.lock().unwrap().push((t, s))), Duration::from_secs(60));
        let mut peers = vec![];
        for i in 1..=9u8 {
            peers.push(TcpStream::connect(addr).await.unwrap());
            let (stream, _) = raw.accept().await.unwrap();
            admit.deliver(stream, IpAddr::from([10, 0, 0, i]));
        }
        assert_eq!(handed.lock().unwrap().len(), 8, "the ninth, from a ninth address, was closed");
        let mut byte = [0u8; 1];
        assert!(matches!(within(peers[8].read(&mut byte)).await, Ok(0) | Err(_)), "without a byte");
        let (_, slot) = handed.lock().unwrap().remove(0);
        slot.finish();
        peers.push(TcpStream::connect(addr).await.unwrap());
        let (stream, _) = raw.accept().await.unwrap();
        admit.deliver(stream, IpAddr::from([10, 0, 0, 9]));
        assert_eq!(handed.lock().unwrap().len(), 8, "a place that was freed is used again");
    }

    /// One connection taken in by an `Admit` that waits `handshake` for it: the server's transport, its slot, and the client's socket.
    async fn delivered(handshake: Duration) -> (Arc<TcpTransport>, PendingSlot, TcpStream) {
        let raw = TcpListener::bind(lo()).await.unwrap();
        let client = TcpStream::connect(raw.local_addr().unwrap()).await.unwrap();
        let (stream, from) = raw.accept().await.unwrap();
        let got: Arc<StdMutex<Vec<(Arc<TcpTransport>, PendingSlot)>>> = Arc::new(StdMutex::new(Vec::new()));
        let g = got.clone();
        Admit::new(Arc::new(move |t, s| g.lock().unwrap().push((t, s))), handshake).deliver(stream, from.ip());
        let (t, s) = got.lock().unwrap().remove(0);
        (t, s, client)
    }

    // The service and the timer can finish a slot at the same moment: only the one that finished it first acts, so a connection the service has just finished is never cut by the timer.
    #[tokio::test]
    async fn only_the_first_finish_of_a_slot_counts_and_the_watchdog_cuts_only_when_it_is_first() {
        let (_t, slot, _c) = delivered(Duration::from_secs(60)).await;
        assert!(slot.finish(), "the first finish says so");
        assert!(!slot.finish(), "the second does not");
        let cut = AtomicBool::new(false);
        expire(&slot, || cut.store(true, Ordering::SeqCst));
        assert!(!cut.load(Ordering::SeqCst), "the service finished it first: the timer leaves the connection alone");
        let (_t2, slot2, _c2) = delivered(Duration::from_secs(60)).await;
        expire(&slot2, || cut.store(true, Ordering::SeqCst));
        assert!(cut.load(Ordering::SeqCst) && slot2.is_finished(), "the timer was first: it cuts and frees the place");
    }

    // Paused time: the service finishes at 9 s, the timer would have fired at 10 s, and the connection is still there afterwards.
    #[tokio::test(start_paused = true)]
    async fn a_connection_finished_before_the_handshake_clock_runs_out_is_not_cut() {
        let (server, slot, _client) = delivered(Duration::from_secs(10)).await;
        tokio::time::advance(Duration::from_secs(9)).await;
        assert!(slot.finish());
        tokio::time::advance(Duration::from_secs(2)).await;
        tokio::task::yield_now().await;
        assert!(server.send(vec![1]).await.is_ok(), "still open");
    }

    #[test]
    fn the_listener_numbers_are_the_macs_and_the_reviews_numbers() {
        assert_eq!((MAX_PENDING, MAX_PENDING_PER_SOURCE, HANDSHAKE_SECONDS), (8, 2, 10));
    }
}
