// The link's one holder (sub-project G2): the listener and its advert, the browser, the pairing, the cards, the receiving and the sending, joined into one service that the app talks to. The
// Mac's twin is LinkService.swift, with every fix of its reviews. It is an actor: one task owns all the state and handles one command at a time, and everything that runs for a while (a
// pairing, a transfer, a send, the listener's connections) is a task of its own that reports back with a command, so the decisions are made in one place and in order.
//
// What makes it safe to leave running:
//   * **Nothing listens until the user turns Visible on** (off by default). No listener, no advert, no firewall prompt before that; the browser runs only while Settings → Devices or the shelf is
//     on screen. Turning Visible off stops the listener, cancels what is running and cuts the connections, and every late event of those is made stale (`RunGate`).
//   * **An incoming pairing runs only while Devices is open, or within 2 minutes after the user clicked Pair here** (`pairing::Gate`); otherwise the hello is refused silently.
//   * **The island has one card** (`CardRules`): a pairing code or an offer from another machine never replaces a card the user is about to click, and a click is ignored for 700 ms after the
//     card changed kind and when it was meant for a card that is gone.
//   * **One transfer for the whole machine** (`Busy`), 8 connections in all and 2 per machine (`ConnectionCaps`), the paired machines read again at most once in 5 s (`ReadLimit`).
//   * **Only a click accepts an offer.** Nothing in this file calls `respond(true)` except `respond_offer(true)`, which only a click reaches.
//   * **No name, size, address or id reaches the log**: the log lines are fixed sentences.

use std::collections::{BTreeMap, HashMap};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use serde::Serialize;
use tokio::sync::{mpsc, oneshot, Notify};

use super::bytes::hex;
use super::cards::{self, offer_key, Busy, CardRules, ConnectionCaps, Kind, ReadLimit, RunGate, Shown, Ticket};
use super::channel::{IdleWatch, Transport};
use super::directory::{self, Row};
use super::discovery::{Discovery, Found};
use super::files::{Source, SourceError};
use super::frames::{decode_preamble, device_name, Advert, Mode, Preamble};
use super::identity::{Identity, Peer};
use super::keystore::{KeyError, Keystore, SecretStore};
use super::net::{Listener, PendingSlot, TcpTransport, HANDSHAKE_SECONDS};
use super::pair_run::{pair_channel, run_incoming, run_initiator, Clock, PairHandle, PairHooks, PairOutcome};
use super::pairing::{Gate, Ids, Initiator, OwnId, Refusal, Responder};
use super::settings::{self, LinkSettings};
use super::transfer::{receive_channel, run_receive, run_send, send_channel, Offer, ReceiveHandle, ReceiveHooks, ReceiveTimings, SendHandle, SendHooks, SendTimings, TransferOutcome};

// ── What the page sees ───────────────────────────────────────────────────────

/// One card on the island. `kind` is `pair`, `offer`, `receiving` or `result`; `key` says what it is about (a click carries it back so that it acts only on the card it was meant for).
#[derive(Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardView {
    pub kind: &'static str,
    pub key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub answered: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub received: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// A result with a saved file: the card offers "Show in folder".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub can_reveal: Option<bool>,
}

#[derive(Clone, PartialEq, Eq, Serialize)]
pub struct RowView {
    pub id: String,
    pub name: String,
    pub state: &'static str,
}

/// Everything the page needs, whole, every time something changes. The page keeps the last one.
#[derive(Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub visible: bool,
    pub name: String,
    pub listening: bool,
    pub problem: Option<String>,
    pub note: Option<String>,
    pub rows: Vec<RowView>,
    pub card: Option<CardView>,
    pub send_status: Option<String>,
    pub sending: bool,
    pub folder: String,
}

/// What the page is given, a click carries and the island shows holds names, ids, sizes and paths: none of it prints. A `{:?}` of any of them is a fixed label (the other types of the link do the same).
macro_rules! fixed_label {
    ($($t:ident),*) => {$(
        impl std::fmt::Debug for $t {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.debug_struct(stringify!($t)).finish_non_exhaustive()
            }
        }
    )*};
}
fixed_label!(CardView, RowView, Snapshot, ShownView, Card);

/// Where the service's news goes (the app turns them into events for the pages) and the log.
pub trait Emit: Send + Sync + 'static {
    fn snapshot(&self, snapshot: &Snapshot);
    /// A fixed sentence: never a name, a size, an address or an id.
    fn log(&self, line: &'static str);
}

// ── Setup ────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct Config {
    /// `link.json`.
    pub settings_path: PathBuf,
    /// `Downloads/NotchMeow`.
    pub folder: PathBuf,
    /// The computer's name, for the default device name only.
    pub host: String,
    /// The mark of the web on received files (Windows).
    pub mark: bool,
    /// `0.0.0.0:0` on the network; `127.0.0.1:0` in the tests.
    pub bind: SocketAddr,
    pub handshake: Duration,
    pub connect_timeout: Duration,
    pub receive: ReceiveTimings,
    pub send: SendTimings,
}

impl Config {
    pub fn app(settings_path: PathBuf, folder: PathBuf, host: String) -> Config {
        Config {
            settings_path,
            folder,
            host,
            mark: super::files::MARK_BY_HAND,
            bind: "0.0.0.0:0".parse().unwrap(),
            handshake: Duration::from_secs(HANDSHAKE_SECONDS),
            connect_timeout: Duration::from_secs(10),
            receive: ReceiveTimings::default(),
            send: SendTimings::default(),
        }
    }
}

pub struct Deps {
    pub keystore: Arc<Keystore<Arc<dyn SecretStore>>>,
    pub discovery: Arc<dyn Discovery>,
    pub emit: Arc<dyn Emit>,
}

impl<T: SecretStore + ?Sized> SecretStore for Arc<T> {
    fn get(&self, account: &str) -> super::keystore::Lookup {
        (**self).get(account)
    }
    fn put(&self, account: &str, value: &str) -> Result<(), super::keystore::StoreError> {
        (**self).put(account, value)
    }
    fn delete(&self, account: &str) -> Result<(), super::keystore::StoreError> {
        (**self).delete(account)
    }
}

/// The platform's words for a credential store that cannot be read.
pub fn key_problem() -> &'static str {
    if cfg!(windows) {
        "The link's key could not be read from the Windows Credential Manager. Nothing is kept in a file instead."
    } else {
        "The link's key could not be read from the Secret Service (GNOME Keyring or KWallet). Start or unlock it: nothing is kept in a file instead, so the link stays off until it works."
    }
}
/// A name goes into the advert only if a card on the other machine would show it (`frames::device_name`). The check is made here, before every `advertise`, whatever made the name.
fn advertisable(name: &str) -> bool {
    device_name(name.as_bytes()).is_ok()
}

/// Progress is the same card with more bytes: a tick reaches the page at most every 100 ms, and the last one always does.
#[derive(Default)]
struct Pace(i64);

impl Pace {
    fn due(&mut self, now: i64, end: bool) -> bool {
        if end || now - self.0 >= 100 {
            self.0 = now;
            true
        } else {
            false
        }
    }
}

const PEERS_PROBLEM: &str = "The paired machines could not be read from the credential store.";
const LISTEN_PROBLEM: &str = "This computer could not start listening.";
const ADVERT_PROBLEM: &str = "This computer could not announce itself on the network.";

// ── Commands ─────────────────────────────────────────────────────────────────

/// The card a click was meant for, as the page saw it.
#[derive(Clone, PartialEq, Eq, serde::Deserialize)]
pub struct ShownView {
    pub kind: String,
    pub key: String,
}

/// The card a click was meant for: None inside means "the one on the island"; the outer None is a click whose kind is not one of ours (ignored).
fn parse_shown(shown: &Option<ShownView>) -> Option<Option<Shown>> {
    match shown {
        None => Some(None),
        Some(s) => s.to_shown().map(Some),
    }
}

impl ShownView {
    fn to_shown(&self) -> Option<Shown> {
        let kind = match self.kind.as_str() {
            "pair" => Kind::Pair,
            "offer" => Kind::Offer,
            "receiving" => Kind::Receiving,
            "result" => Kind::Result,
            _ => return None,
        };
        Some(Shown { kind, key: self.key.clone() })
    }
}

enum Cmd {
    // From the app.
    Start,
    SetVisible(bool),
    SetName(String, oneshot::Sender<bool>),
    DevicesOpen(bool),
    ShelfOpen(bool),
    Pair(String),
    AnswerPair(bool, Option<ShownView>),
    RespondOffer(bool, Option<ShownView>),
    CancelReceiving(Option<ShownView>),
    Dismiss(Option<ShownView>),
    Forget(String),
    Send(Vec<PathBuf>, String),
    CancelSending,
    RevealPath(oneshot::Sender<Option<PathBuf>>),
    Snapshot(oneshot::Sender<Snapshot>),
    // From the tasks the service started.
    Browsed(Vec<Found>, u64),
    Preamble { conn: u64, transport: Arc<TcpTransport>, slot: PendingSlot, gen: u64, pre: Preamble },
    Track { conn: u64, transport: Arc<TcpTransport>, gen: u64 },
    Untrack(u64),
    OutboundFailed(u64),
    PairCode { ticket: Ticket, code: String, name: String },
    PairEnded { outcome: PairOutcome, initiator: Option<Initiator>, responder: Option<Responder>, own_id: String, gen: u64, outbound: bool },
    IncomingRefused(u64),
    OfferArrived { offer: Offer, handle: ReceiveHandle, conn: u64, gen: u64 },
    Progress { conn: u64, got: u64 },
    ReceiveEnded { conn: u64, outcome: TransferOutcome, gen: u64, handle: ReceiveHandle, peer_id: String },
    SendStatus(String, u64),
    SendDone(u64),
}

/// The handle the app holds. Every method only posts a command; the actor does the work.
#[derive(Clone)]
pub struct Service {
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Service {
    /// `spawner` starts the actor on the app's async runtime (`|f| { tauri::async_runtime::spawn(f); }`; the tests pass `|f| { tokio::spawn(f); }`): this folder knows no Tauri type.
    pub fn spawn(spawner: impl FnOnce(std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>), cfg: Config, deps: Deps) -> Service {
        let (tx, rx) = mpsc::unbounded_channel();
        let settings = settings::load(&cfg.settings_path, &cfg.host);
        let core = Core::new(cfg, deps, settings, tx.clone());
        spawner(Box::pin(core.run(rx)));
        Service { tx }
    }

    fn post(&self, c: Cmd) {
        let _ = self.tx.send(c);
    }

    /// At launch: with Visible on, reads the paired machines and starts the listener. With Visible off nothing from the credential store is read, made or written at launch: the paired list loads when Visible is turned on or when Devices comes on screen, and when the shelf comes on screen with Visible on.
    pub fn start(&self) {
        self.post(Cmd::Start);
    }
    pub fn set_visible(&self, on: bool) {
        self.post(Cmd::SetVisible(on));
    }
    /// False when the name is not one a card would accept.
    pub async fn set_device_name(&self, name: String) -> bool {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::SetName(name, tx));
        rx.await.unwrap_or(false)
    }
    /// Settings → Devices is on screen (or not): while it is, another machine may start a pairing with this one, and the machines are looked for. It says how things are now, not what
    /// changed, so saying it twice changes nothing and a missed "closed" is put right by the next one.
    pub fn set_devices_open(&self, open: bool) {
        self.post(Cmd::DevicesOpen(open));
    }
    /// The shelf is on screen (or not): while it is, the machines are looked for.
    pub fn set_shelf_open(&self, open: bool) {
        self.post(Cmd::ShelfOpen(open));
    }
    /// "Pair a machine": this machine starts a pairing with a machine it has seen.
    pub fn pair(&self, id: String) {
        self.post(Cmd::Pair(id));
    }
    pub fn answer_pair(&self, yes: bool, shown: Option<ShownView>) {
        self.post(Cmd::AnswerPair(yes, shown));
    }
    /// The only way an offer is accepted: a click on Accept.
    pub fn respond_offer(&self, accept: bool, shown: Option<ShownView>) {
        self.post(Cmd::RespondOffer(accept, shown));
    }
    pub fn cancel_receiving(&self, shown: Option<ShownView>) {
        self.post(Cmd::CancelReceiving(shown));
    }
    /// The OK on a result, or the close of any card.
    pub fn dismiss(&self, shown: Option<ShownView>) {
        self.post(Cmd::Dismiss(shown));
    }
    pub fn forget(&self, id: String) {
        self.post(Cmd::Forget(id));
    }
    /// Sends these files, one connection for each, one after the other, each needing the other user's Accept.
    pub fn send(&self, paths: Vec<PathBuf>, to: String) {
        self.post(Cmd::Send(paths, to));
    }
    pub fn cancel_sending(&self) {
        self.post(Cmd::CancelSending);
    }
    /// The file the result card is about, for "Show in folder".
    pub async fn result_file(&self) -> Option<PathBuf> {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::RevealPath(tx));
        rx.await.ok().flatten()
    }
    pub async fn snapshot(&self) -> Option<Snapshot> {
        let (tx, rx) = oneshot::channel();
        self.post(Cmd::Snapshot(tx));
        rx.await.ok()
    }
}

// ── The core ─────────────────────────────────────────────────────────────────

#[derive(Clone, PartialEq, Eq)]
enum Card {
    Pair { code: String, peer: String, answered: bool },
    Offer(Offer),
    Receiving(Offer, u64),
    Result { title: String, detail: String, file: Option<PathBuf> },
}

impl Card {
    /// The flow a card with buttons belongs to. A result is given the flow that ended by that flow itself.
    fn flow(&self) -> Option<String> {
        match self {
            Card::Pair { code, peer, .. } => Some(format!("pair:{code}|{peer}")),
            Card::Offer(o) | Card::Receiving(o, _) => Some(format!("transfer:{}", offer_key(&o.peer_id, &o.transfer_id))),
            Card::Result { .. } => None,
        }
    }

    fn shown(&self) -> Shown {
        match self {
            Card::Pair { code, peer, .. } => Shown { kind: Kind::Pair, key: format!("{code}|{peer}") },
            Card::Offer(o) => Shown { kind: Kind::Offer, key: offer_key(&o.peer_id, &o.transfer_id) },
            Card::Receiving(o, _) => Shown { kind: Kind::Receiving, key: offer_key(&o.peer_id, &o.transfer_id) },
            Card::Result { title, detail, .. } => Shown { kind: Kind::Result, key: format!("{title}|{detail}") },
        }
    }

    fn holds_island(&self) -> bool {
        !matches!(self, Card::Result { .. })
    }

    fn view(&self) -> CardView {
        let s = self.shown();
        let base = CardView { kind: kind_word(s.kind), key: s.key, code: None, peer: None, answered: None, name: None, size: None, received: None, title: None, detail: None, can_reveal: None };
        match self {
            Card::Pair { code, peer, answered } => CardView { code: Some(code.clone()), peer: Some(peer.clone()), answered: Some(*answered), ..base },
            Card::Offer(o) => CardView { name: Some(o.name.clone()), size: Some(o.size), peer: Some(o.peer_name.clone()), ..base },
            Card::Receiving(o, got) => CardView { name: Some(o.name.clone()), size: Some(o.size), received: Some(*got), peer: Some(o.peer_name.clone()), ..base },
            Card::Result { title, detail, file } => CardView { title: Some(title.clone()), detail: Some(detail.clone()), can_reveal: Some(file.is_some()), ..base },
        }
    }
}

fn kind_word(k: Kind) -> &'static str {
    match k {
        Kind::Pair => "pair",
        Kind::Offer => "offer",
        Kind::Receiving => "receiving",
        Kind::Result => "result",
    }
}

struct Own {
    device_id: String,
    key: [u8; 32],
    public: [u8; 32],
}

struct Receiving {
    conn: u64,
    ticket: Ticket,
    handle: ReceiveHandle,
    flow: String,
}

/// What a send in progress is made of, shared between the actor and the task that does it.
struct SendControl {
    /// The machine the files go to: forgetting it cancels the send.
    peer_id: String,
    cancelled: AtomicBool,
    handle: StdMutex<Option<SendHandle>>,
    connecting: Notify,
}

struct Core {
    cfg: Config,
    deps: Deps,
    tx: mpsc::UnboundedSender<Cmd>,
    settings: LinkSettings,
    rows: Vec<Row>,
    listening: bool,
    problem: Option<String>,
    note: Option<String>,
    card: Option<Card>,
    send_status: Option<String>,
    sending: bool,
    listener: Option<Listener>,
    devices_open: bool,
    shelf_open: bool,
    browse_token: Option<u64>,
    seen: HashMap<String, Found>,
    pairing: (Initiator, Responder),
    pair_handle: Option<PairHandle>,
    pair_gate: Gate,
    pairing_incoming: bool,
    outbound: bool,
    receive: Option<Receiving>,
    send_control: Option<Arc<SendControl>>,
    busy: Arc<Busy>,
    caps: Arc<ConnectionCaps>,
    peers: BTreeMap<String, Peer>,
    peers_loaded: bool,
    read_limit: ReadLimit,
    own: Option<Own>,
    rules: CardRules,
    pair_flow: Option<String>,
    gate: RunGate,
    active: HashMap<u64, Arc<TcpTransport>>,
    next: Arc<AtomicU64>,
    last_published: Option<Snapshot>,
    pace: Pace,
}

fn clock() -> Clock {
    Arc::new(cards::now_ms)
}

fn random32() -> [u8; 32] {
    let mut b = [0u8; 32];
    let _ = getrandom::getrandom(&mut b);
    b
}

impl Core {
    fn new(cfg: Config, deps: Deps, settings: LinkSettings, tx: mpsc::UnboundedSender<Cmd>) -> Core {
        Core {
            cfg,
            deps,
            tx,
            settings,
            rows: vec![],
            listening: false,
            problem: None,
            note: None,
            card: None,
            send_status: None,
            sending: false,
            listener: None,
            devices_open: false,
            shelf_open: false,
            browse_token: None,
            seen: HashMap::new(),
            pairing: (Initiator::new(Ids::default()), Responder::new(Ids::default())),
            pair_handle: None,
            pair_gate: Gate::default(),
            pairing_incoming: false,
            outbound: false,
            receive: None,
            send_control: None,
            busy: Arc::new(Busy::default()),
            caps: Arc::new(ConnectionCaps::default()),
            peers: BTreeMap::new(),
            peers_loaded: false,
            read_limit: ReadLimit::default(),
            own: None,
            rules: CardRules::default(),
            pair_flow: None,
            gate: RunGate::default(),
            active: HashMap::new(),
            next: Arc::new(AtomicU64::new(1)),
            last_published: None,
            pace: Pace::default(),
        }
    }

    async fn run(mut self, mut rx: mpsc::UnboundedReceiver<Cmd>) {
        while let Some(cmd) = rx.recv().await {
            let tick = matches!(cmd, Cmd::Progress { .. });
            self.handle(cmd).await;
            if !tick {
                self.publish(false); // a progress tick says by itself when it is shown (`Pace`)
            }
        }
    }

    fn id(&self) -> u64 {
        self.next.fetch_add(1, Ordering::SeqCst) + 1
    }

    fn generation(&self) -> u64 {
        self.gate.generation()
    }

    fn log(&self, line: &'static str) {
        self.deps.emit.log(line);
    }

    fn snapshot(&self) -> Snapshot {
        Snapshot {
            visible: self.settings.visible,
            name: self.settings.device_name.clone(),
            listening: self.listening,
            problem: self.problem.clone(),
            note: self.note.clone(),
            rows: self.rows.iter().map(|r| RowView { id: r.id.clone(), name: r.name.clone(), state: r.state.as_str() }).collect(),
            card: self.card.as_ref().map(Card::view),
            send_status: self.send_status.clone(),
            sending: self.sending,
            folder: self.cfg.folder.display().to_string(),
        }
    }

    /// Tells the page, when something it shows has changed. `force` is for progress ticks, which are the same card with more bytes and are let through at most every 100 ms.
    fn publish(&mut self, force: bool) {
        let now = self.snapshot();
        if !force && self.last_published.as_ref() == Some(&now) {
            return;
        }
        self.deps.emit.snapshot(&now);
        self.last_published = Some(now);
    }

    async fn handle(&mut self, cmd: Cmd) {
        match cmd {
            Cmd::Start => {
                // Visible is off until the user turns it on: a launch then reads nothing from the credential store (no prompt, no problem line, no id or key made). The paired machines are read when
                // Visible is on, or when Devices or the shelf comes on screen.
                if self.settings.visible {
                    self.reload_peers();
                    self.start_listening().await;
                }
            }
            Cmd::SetVisible(on) => self.set_visible(on).await,
            Cmd::SetName(name, reply) => {
                let ok = self.set_device_name(&name).await;
                let _ = reply.send(ok);
            }
            Cmd::DevicesOpen(open) => {
                if open == self.devices_open {
                    if open {
                        self.start_browser(); // the page says it again: a search that ended by itself is made again (the gate counts transitions only)
                    }
                    return;
                }
                self.devices_open = open;
                if open {
                    self.pair_gate.devices_appeared();
                    self.reload_peers();
                    if self.settings.visible && !self.listening {
                        self.start_listening().await;
                    }
                    self.start_browser();
                } else {
                    self.pair_gate.devices_disappeared();
                    self.looking_ended();
                }
            }
            Cmd::ShelfOpen(open) => {
                if open == self.shelf_open {
                    if open {
                        self.start_browser();
                    }
                    return;
                }
                self.shelf_open = open;
                if open {
                    // Devices reads the store so that Forget stays reachable; the shelf does not: with Visible off it says nothing about the store.
                    if self.settings.visible && !self.peers_loaded {
                        self.reload_peers();
                    }
                    self.start_browser();
                } else {
                    self.looking_ended();
                }
            }
            Cmd::Browsed(results, token) => {
                if self.browse_token == Some(token) {
                    self.seen = results.into_iter().map(|f| (f.advert.id.clone(), f)).collect();
                    self.refresh_rows();
                }
            }
            Cmd::Pair(id) => self.pair(&id).await,
            Cmd::AnswerPair(yes, shown) => self.answer_pair(yes, shown),
            Cmd::RespondOffer(accept, shown) => self.respond_offer(accept, shown),
            Cmd::CancelReceiving(shown) => self.cancel_receiving(shown),
            Cmd::Dismiss(shown) => self.dismiss(shown),
            Cmd::Forget(id) => self.forget(&id),
            Cmd::Send(paths, to) => self.send(paths, &to).await,
            Cmd::CancelSending => self.cancel_sending(),
            Cmd::RevealPath(reply) => {
                let _ = reply.send(match &self.card {
                    Some(Card::Result { file, .. }) => file.clone(),
                    _ => None,
                });
            }
            Cmd::Snapshot(reply) => {
                let _ = reply.send(self.snapshot());
            }
            Cmd::Preamble { conn, transport, slot, gen, pre } => self.preamble(conn, transport, slot, gen, pre).await,
            Cmd::Track { conn, transport, gen } => {
                if gen == self.generation() {
                    self.active.insert(conn, transport);
                } else {
                    transport.abort(); // Visible was turned off while connecting
                }
            }
            Cmd::Untrack(conn) => {
                self.active.remove(&conn);
            }
            Cmd::OutboundFailed(gen) => {
                if gen == self.generation() {
                    self.outbound = false;
                    self.pair_handle = None;
                    self.gate.end_pair();
                    self.note = Some("Could not reach that machine.".into());
                }
            }
            Cmd::PairCode { ticket, code, name } => self.code_known(ticket, code, name),
            Cmd::PairEnded { outcome, initiator, responder, own_id, gen, outbound } => self.pair_ended(outcome, initiator, responder, &own_id, gen, outbound),
            Cmd::IncomingRefused(gen) => {
                if gen == self.generation() {
                    self.pairing_incoming = false;
                    self.pair_handle = None;
                    self.gate.end_pair();
                }
            }
            Cmd::OfferArrived { offer, handle, conn, gen } => self.offer_arrived(offer, handle, conn, gen),
            Cmd::Progress { conn, got } => self.progressed(conn, got),
            Cmd::ReceiveEnded { conn, outcome, gen, handle, peer_id } => self.receive_ended(conn, outcome, gen, handle, &peer_id),
            Cmd::SendStatus(text, gen) => {
                if gen == self.generation() && self.sending {
                    self.send_status = Some(text);
                }
            }
            Cmd::SendDone(gen) => {
                if gen == self.generation() {
                    self.sending = false;
                    self.send_control = None;
                }
            }
        }
    }

    // ── Start, stop, settings ──

    async fn set_visible(&mut self, on: bool) {
        if on == self.settings.visible {
            return;
        }
        self.settings.visible = on;
        let _ = settings::save(&self.cfg.settings_path, &self.settings);
        if on {
            self.reload_peers();
            self.start_listening().await;
            self.start_browser(); // Devices or the shelf was already open: turning Visible on starts the search
        } else {
            self.stop_listening();
            self.stop_browser();
        }
        self.refresh_rows();
    }

    /// The one place the advert is made or changed: a name a card would refuse is not announced.
    fn announce(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
        if !advertisable(name) {
            return Err(ADVERT_PROBLEM.into());
        }
        self.deps.discovery.advertise(id, name, port)
    }

    /// False when the name is not one a card would accept.
    async fn set_device_name(&mut self, name: &str) -> bool {
        let Some(valid) = settings::valid_name(Some(&serde_json::Value::String(name.to_string()))) else { return false };
        if valid == self.settings.device_name {
            return true;
        }
        self.settings.device_name = valid;
        let _ = settings::save(&self.cfg.settings_path, &self.settings);
        // The advert carries the name, so it is announced again. Connections that were accepted are sockets of their own and the conversations on them do not depend on the listener: a pairing or a
        // transfer that is running is not touched (this is not `stop_listening`).
        if let (true, Some(l)) = (self.settings.visible, &self.listener) {
            if let Some(own) = &self.own {
                if self.announce(&own.device_id, &self.settings.device_name, l.port()).is_err() {
                    self.problem = Some(ADVERT_PROBLEM.into());
                }
            }
        }
        true
    }

    fn report(&mut self, line: &str, failed: bool) {
        if failed {
            self.problem = Some(line.to_string());
        } else if self.problem.as_deref() == Some(line) {
            self.problem = None;
        }
    }

    /// This machine's identity, from memory once it has been read. A read that fails is not kept: the next call reads again, and Devices says it could not be read until one works.
    fn identity(&mut self) -> Option<Identity> {
        if self.own.is_none() {
            let read = (|| -> Result<Own, KeyError> {
                let device_id = self.deps.keystore.device_id()?;
                let (key, public) = self.deps.keystore.static_key()?;
                Ok(Own { device_id, key, public })
            })();
            match read {
                Ok(own) => {
                    self.own = Some(own);
                    self.report(key_problem(), false);
                }
                Err(_) => {
                    self.report(key_problem(), true);
                    return None;
                }
            }
        }
        let o = self.own.as_ref()?;
        Some(Identity { device_id: o.device_id.clone(), name: self.settings.device_name.clone(), key: o.key, public: o.public })
    }

    /// The device id alone, for the browser and the list (they do not need the key): from memory, or read once.
    fn device_id(&mut self) -> Option<String> {
        if self.own.is_none() {
            let _ = self.identity();
        }
        self.own.as_ref().map(|o| o.device_id.clone())
    }

    async fn start_listening(&mut self) {
        if self.listener.is_some() {
            return;
        }
        let Some(me) = self.identity() else { return };
        let (tx, gen, ids) = (self.tx.clone(), self.generation(), self.next.clone());
        let on_connection: super::net::OnConnection = Arc::new(move |transport, slot| {
            let (tx, conn) = (tx.clone(), ids.fetch_add(1, Ordering::SeqCst) + 1);
            // The service holds the connection from the moment it is accepted, so that turning Visible off cuts it at once: `Listener::stop` only bounds the ones that are still waiting (by the
            // watchdog, 10 s later).
            let _ = tx.send(Cmd::Track { conn, transport: transport.clone(), gen });
            tokio::spawn(async move {
                // The first record comes first: nothing is looked up, read from the credential store or decided for a connection that has not sent a valid one. The slot's watchdog bounds the wait.
                let pre = match transport.receive().await.ok().and_then(|r| decode_preamble(&r).ok()) {
                    Some(p) => p,
                    None => {
                        slot.finish();
                        transport.close().await;
                        let _ = tx.send(Cmd::Untrack(conn));
                        return;
                    }
                };
                let _ = tx.send(Cmd::Preamble { conn, transport, slot, gen, pre });
            });
        });
        match Listener::start(self.cfg.bind, on_connection, self.cfg.handshake).await {
            Ok(l) => {
                let port = l.port();
                match self.announce(&me.device_id, &me.name, port) {
                    Ok(()) => {
                        self.listener = Some(l);
                        self.listening = true;
                        if self.problem.as_deref() == Some(LISTEN_PROBLEM) || self.problem.as_deref() == Some(ADVERT_PROBLEM) {
                            self.problem = None;
                        }
                        self.log("listening");
                    }
                    Err(_) => {
                        l.stop();
                        self.problem = Some(ADVERT_PROBLEM.into());
                    }
                }
            }
            Err(_) => {
                self.listening = false;
                self.problem = Some(LISTEN_PROBLEM.into());
            }
        }
    }

    /// Visible turned off: nothing keeps running. Conversations are cancelled and their connections cut (also those that have no run yet), and everything that was awaiting is made stale by the
    /// new generation. A card that belonged to one of them goes, since nothing is left to answer.
    fn stop_listening(&mut self) {
        self.gate.stop();
        self.listener = None;
        self.deps.discovery.stop_advertising();
        self.listening = false;
        if let Some(h) = self.pair_handle.take() {
            h.cancel();
        }
        if let Some(r) = self.receive.take() {
            r.handle.cancel();
        }
        if let Some(c) = self.send_control.take() {
            c.cancelled.store(true, Ordering::SeqCst);
            if let Some(h) = c.handle.lock().unwrap().take() {
                h.cancel();
            }
            c.connecting.notify_waiters();
        }
        self.outbound = false;
        self.pairing_incoming = false;
        self.sending = false;
        self.pair_flow = None;
        self.send_status = None;
        for (_, t) in self.active.drain() {
            t.abort();
        }
        self.rules = CardRules::default();
        self.card = None;
        self.busy.set_card_locked(false);
        self.log("stopped listening");
    }

    // ── Browsing (only while Devices or the shelf is open) ──

    /// Someone is looking at the machines: Devices or the shelf.
    fn looking(&self) -> bool {
        self.devices_open || self.shelf_open
    }

    /// One of them stopped looking: the search ends when both have.
    fn looking_ended(&mut self) {
        if self.looking() {
            return;
        }
        self.stop_browser();
        if !self.sending {
            self.send_status = None; // the last line of a finished send does not wait for the next time the shelf opens
        }
        self.refresh_rows();
    }

    /// Starts the search, or asks for it again: `Discovery::browse` leaves a search that is running alone. (`Mdns` watches its own daemon and search and makes them again after a death, by the restart rule, so this does not
    /// have to revive one.) It is called every time Devices or the shelf comes on screen and when Visible is turned on, and the token stays the same while someone looks.
    fn start_browser(&mut self) {
        if !self.looking() || !self.settings.visible {
            return;
        }
        let Some(id) = self.device_id() else { return };
        let token = self.browse_token.unwrap_or_else(|| self.id());
        let tx = self.tx.clone();
        match self.deps.discovery.browse(&id, Arc::new(move |results| { let _ = tx.send(Cmd::Browsed(results, token)); })) {
            Ok(()) => self.browse_token = Some(token),
            Err(_) => {
                self.browse_token = None;
                self.note = Some("This computer could not look for other machines.".into());
            }
        }
    }

    fn stop_browser(&mut self) {
        // `stop_browsing` waits for a result that is being handed up; that result only posts a command (`Cmd::Browsed`), so nothing here can be waiting on this actor, and no lock is held.
        if self.browse_token.take().is_some() {
            self.deps.discovery.stop_browsing();
        }
        self.seen.clear();
    }

    /// Builds the list from what is in memory: no credential-store read (the browser may report many times a second), and no id or key made: the own id is the one that was read when the machine
    /// was made visible (a machine that is not looking for others has none, and its own advert is never in the list).
    fn refresh_rows(&mut self) {
        let own = self.own.as_ref().map(|o| o.device_id.clone()).unwrap_or_default();
        let adverts: Vec<Advert> = self.seen.values().map(|f| f.advert.clone()).collect();
        self.rows = directory::rows(&adverts, &self.peers, &own);
    }

    /// The read of the paired machines: at launch, when Visible is turned on, when Devices opens, on a miss, and after a pairing was stored or a machine forgotten. A read that cannot be trusted
    /// (an item that will not read, or nothing at all where there were machines) keeps the last good map and puts a line in Devices.
    fn reload_peers(&mut self) {
        self.read_limit.read(cards::now_ms());
        match self.deps.keystore.paired_machines(!self.peers.is_empty()) {
            Ok(map) => {
                self.peers = map;
                self.peers_loaded = true;
                self.report(PEERS_PROBLEM, false);
            }
            Err(_) => self.report(PEERS_PROBLEM, true),
        }
        self.refresh_rows();
    }

    /// A paired machine, from memory; when it is not there the store is read again, at most once in 5 s, so a read that failed for a moment does not leave a paired machine unknown until the next
    /// launch, and a peer that sends ids that are not paired cannot make this machine read the store in a loop.
    fn paired_peer(&mut self, id: &str) -> Option<Peer> {
        if !self.peers.contains_key(id) && self.read_limit.due(cards::now_ms()) {
            self.reload_peers();
        }
        self.peers.get(id).cloned()
    }

    fn forget(&mut self, id: &str) {
        let failed = self.deps.keystore.forget(id).is_err();
        self.peers.remove(id); // so that what is left is the whole map, and a read that finds none is a failed one
        self.refuse_transfer_from(id);
        if self.send_control.as_ref().is_some_and(|c| c.peer_id == id) {
            self.cancel_sending(); // what was still to go to a machine that is no longer trusted is not sent
        }
        self.reload_peers();
        if failed {
            self.problem = Some(PEERS_PROBLEM.into()); // after the read: a read that works must not wipe the line of a forget that did not
        }
    }

    /// A machine that was just forgotten is no longer trusted: an offer of it that waits for a click is declined and a file of it that comes in is cancelled, and the card goes now, so no click
    /// can accept or complete what that machine started. The run answers for its own end.
    fn refuse_transfer_from(&mut self, id: &str) {
        let Some(r) = &self.receive else { return };
        let flow = r.flow.clone();
        if self.card.as_ref().and_then(Card::flow).as_deref() != Some(flow.as_str()) {
            return;
        }
        match &self.card {
            Some(Card::Offer(o)) if o.peer_id == id => r.handle.respond(false),
            Some(Card::Receiving(o, _)) if o.peer_id == id => r.handle.cancel(),
            _ => return,
        }
        self.receive = None;
        self.gate.end_receive();
        self.present(None, &flow);
    }

    // ── The card ──

    /// The one way a flow changes the card: `card` is its card, or None to take its card away. False when another flow's card with buttons is on the island (the card is then left as it is, and
    /// nothing is shown), or when `card` is None and the card on the island is not this flow's.
    fn present(&mut self, new: Option<Card>, owner: &str) -> bool {
        match new {
            None => {
                if !self.rules.end(owner) {
                    return false;
                }
                self.card = None;
            }
            Some(card) => {
                if !self.rules.show(card.shown(), owner, cards::now_ms()) {
                    return false;
                }
                self.card = Some(card);
            }
        }
        let hold = self.card.as_ref().is_some_and(Card::holds_island);
        self.busy.set_card_locked(hold); // an offer that arrives now is declined as busy, whatever task its run is on
        true
    }

    // ── Pairing ──

    async fn pair(&mut self, id: &str) {
        if !self.settings.visible {
            self.note = Some("Turn on Visible on this network first.".into());
            return;
        }
        if self.pair_handle.is_some() || self.outbound || self.pairing_incoming {
            return;
        }
        let Some(target) = self.seen.get(id).cloned() else { return };
        let Some(me) = self.identity() else { return };
        if self.rules.interactive() {
            self.note = Some("Answer the card on the island first.".into());
            return;
        }
        self.outbound = true;
        self.pair_gate.pair_clicked(cards::now_ms());
        self.note = None;
        let (gen, conn, ticket) = (self.generation(), self.id(), self.gate.begin_pair());
        let (handle, inbox) = pair_channel();
        self.pair_handle = Some(handle);
        let mut state = self.pairing.0.clone();
        state.ids = self.pair_ids(&me);
        let (tx, timeout, handshake) = (self.tx.clone(), self.cfg.connect_timeout, self.cfg.handshake);
        tokio::spawn(async move {
            let transport = match TcpTransport::connect(target.addr, timeout).await {
                Ok(t) => t,
                Err(_) => {
                    let _ = tx.send(Cmd::OutboundFailed(gen));
                    return;
                }
            };
            let _ = tx.send(Cmd::Track { conn, transport: transport.clone(), gen });
            // The handshake has 10 seconds, as the listener gives one on the other side: a machine that connects and then says nothing does not hold this machine's pairing slot.
            let deadline = Arc::new({
                let t = transport.clone();
                IdleWatch::new(handshake.as_millis() as u64, move || t.abort())
            });
            let (tx_code, tx_done, d2) = (tx.clone(), tx.clone(), deadline.clone());
            let hooks = PairHooks {
                show_code: Arc::new(move |code, name| { let _ = tx_code.send(Cmd::PairCode { ticket, code, name }); }),
                handshake_done: Arc::new(move || d2.stop()),
            };
            let own_id = me.device_id.clone();
            let (outcome, next) = run_initiator(transport, &me, random32(), clock(), state, &hooks, inbox).await;
            deadline.stop();
            let _ = tx_done.send(Cmd::PairEnded { outcome, initiator: Some(next), responder: None, own_id, gen, outbound: true });
            let _ = tx.send(Cmd::Untrack(conn));
        });
    }

    /// The snapshot a pairing starts with: from memory (the store re-reads itself when a key is stored).
    fn pair_ids(&self, me: &Identity) -> Ids {
        Ids { own_id: OwnId::Id(me.device_id.clone()), paired: Some(self.peers.iter().map(|(k, p)| (k.clone(), p.key.clone())).collect()) }
    }

    /// The code of a pairing is known. It takes the card only if no other flow's card with buttons is up (or an offer is claimed and about to take it); otherwise the pairing is ended (nothing was
    /// ever shown for it). A code that comes from a stopped or replaced pairing (`ticket` is not the current one) does nothing, and does not touch the current run.
    fn code_known(&mut self, ticket: Ticket, code: String, name: String) {
        if !self.gate.is_pair(ticket) {
            return;
        }
        let card = Card::Pair { code, peer: name, answered: false };
        let flow = card.flow().unwrap_or_default();
        if self.busy.reserve_card() && self.present(Some(card), &flow) {
            self.pair_flow = Some(flow);
        } else if let Some(h) = &self.pair_handle {
            h.cancel();
        }
    }

    /// The user's click on "They match" or "No". `shown` is the card the click was meant for (None: the one on the island).
    fn answer_pair(&mut self, yes: bool, shown: Option<ShownView>) {
        let Some(Card::Pair { code, peer, answered: false }) = self.card.clone() else { return };
        let card = Card::Pair { code, peer, answered: true };
        let Some(shown) = parse_shown(&shown) else { return };
        if !self.rules.accepts(shown.as_ref(), cards::now_ms()) || self.pair_flow != self.card.as_ref().and_then(Card::flow) {
            return; // pair_flow is set only by the current run's own code
        }
        let Some(handle) = self.pair_handle.clone() else { return };
        let flow = card.flow().unwrap_or_default();
        self.present(Some(card), &flow);
        handle.answer(yes);
    }

    /// `gen` is the generation the pairing started under: after Visible was turned off nothing of it is touched, and only a pairing both users said yes to is kept. `started` is true for a pairing this
    /// user started: only that one may leave a note in Devices (a machine that connects and is refused must not write on this machine's screen).
    fn pair_ended(&mut self, outcome: PairOutcome, initiator: Option<Initiator>, responder: Option<Responder>, own_id: &str, gen: u64, started: bool) {
        let flow = self.pair_flow.clone();
        self.log("a pairing ended");
        if gen != self.generation() {
            // A run of a stopped generation: only what both users agreed to is kept, and the machines it ends with are not the current ones (only the current run writes them).
            if let PairOutcome::Paired(peer) = outcome {
                let _ = self.deps.keystore.add(&peer, own_id);
                self.reload_peers();
            }
            return;
        }
        if let Some(i) = initiator {
            self.pairing.0 = i;
        }
        if let Some(r) = responder {
            self.pairing.1 = r;
        }
        self.pair_handle = None;
        self.outbound = false;
        self.pairing_incoming = false;
        self.pair_flow = None;
        self.gate.end_pair();
        match outcome {
            PairOutcome::Paired(peer) => {
                // Both users said yes. The paired map is read again at the moment of storing (two pairings can overlap for up to two minutes).
                let result = match self.deps.keystore.add(&peer, own_id) {
                    Ok(()) => {
                        self.reload_peers();
                        Card::Result { title: "Paired".into(), detail: format!("This computer and {} can now send files to each other.", peer.name), file: None }
                    }
                    Err(_) => Card::Result { title: "Not paired".into(), detail: "That machine could not be saved.".into(), file: None },
                };
                if let Some(f) = flow {
                    self.present(Some(result), &f);
                }
            }
            PairOutcome::Declined { by_me } => {
                if let Some(f) = flow {
                    let card = if by_me { None } else { Some(Card::Result { title: "Not paired".into(), detail: "The other machine said the codes did not match.".into(), file: None }) };
                    self.present(card, &f);
                }
            }
            PairOutcome::Refused(why) => {
                if let Some(f) = flow {
                    self.present(None, &f);
                }
                if started {
                    self.note = Some(if why == Refusal::AttemptTooSoon.as_str() { "Wait 30 seconds before trying again.".into() } else { "The pairing did not go through.".into() });
                }
            }
        }
        self.refresh_rows();
    }

    // ── Incoming connections ──

    /// `gen` is the generation the listener that accepted the socket was built under: a connection that was accepted before Visible was turned off is closed, however late its task runs.
    async fn preamble(&mut self, conn: u64, transport: Arc<TcpTransport>, slot: PendingSlot, gen: u64, pre: Preamble) {
        // Nothing is accepted while the machine is not visible: a connection that a stopped listener had already taken is closed.
        if gen != self.generation() || !self.settings.visible {
            slot.finish();
            self.active.remove(&conn);
            tokio::spawn(async move { transport.close().await });
            return;
        }
        let tx = self.tx.clone(); // the connection is in `active` already (`Track`, sent when it was accepted)
        match pre.mode {
            Mode::Pair => {
                // Outside the gate (Devices closed and no Pair click in the last 2 minutes), while another pairing runs, or while a card with buttons is on the island: refused silently, nothing sent,
                // no card, no alert. A code from another machine never appears in front of a card the user is about to click.
                let allowed = self.pair_handle.is_none() && !self.outbound && !self.pairing_incoming && !self.rules.interactive() && self.pair_gate.allows(Some(cards::now_ms()));
                let me = if allowed { self.identity() } else { None };
                let Some(me) = me else {
                    slot.finish();
                    self.active.remove(&conn);
                    tokio::spawn(async move { transport.close().await });
                    return;
                };
                self.pairing_incoming = true;
                let ticket = self.gate.begin_pair();
                let (handle, inbox) = pair_channel();
                self.pair_handle = Some(handle);
                let mut state = self.pairing.1.clone();
                state.ids = self.pair_ids(&me);
                let gate = self.pair_gate.clone();
                tokio::spawn(async move {
                    let (tx_code, s2) = (tx.clone(), slot.clone());
                    let hooks = PairHooks {
                        show_code: Arc::new(move |code, name| { let _ = tx_code.send(Cmd::PairCode { ticket, code, name }); }),
                        handshake_done: Arc::new(move || { s2.finish(); }),
                    };
                    let own_id = me.device_id.clone();
                    let result = run_incoming(transport, &me, random32(), clock(), &gate, state, &hooks, inbox).await;
                    slot.finish();
                    match result {
                        None => {
                            let _ = tx.send(Cmd::IncomingRefused(gen));
                        }
                        Some((outcome, next)) => {
                            let _ = tx.send(Cmd::PairEnded { outcome, initiator: None, responder: Some(next), own_id, gen, outbound: false });
                        }
                    }
                    let _ = tx.send(Cmd::Untrack(conn));
                });
            }
            Mode::Transfer => {
                // A transfer runs only between paired machines: an id this machine does not know is closed without an answer.
                let id = hex(&pre.id);
                let (Some(peer), Some(me)) = (self.paired_peer(&id), self.identity()) else {
                    slot.finish();
                    self.active.remove(&conn);
                    tokio::spawn(async move { transport.close().await });
                    return;
                };
                self.log("a transfer started");
                let (busy, caps) = (self.busy.clone(), self.caps.clone());
                let (folder, mark, timings) = (self.cfg.folder.clone(), self.cfg.mark, self.cfg.receive);
                tokio::spawn(async move {
                    // The run is not "the" receive run until its offer is waiting for a click (`OfferArrived`): a connection that has only said hello holds nothing and blocks nobody. A second offer still
                    // gets its answer, "busy" (reason 2), and no card, because its claim fails (`Busy`). The run keeps its transfer place until the service gives it back.
                    let (handle, inbox) = receive_channel();
                    let (t_offer, t_progress, s_done, c_admit, pid) = (tx.clone(), tx.clone(), slot.clone(), caps.clone(), peer.id.clone());
                    let (h_offer, pid2) = (handle.clone(), peer.id.clone());
                    let (b1, b2) = (busy.clone(), busy.clone());
                    let hooks = ReceiveHooks {
                        offered: Arc::new(move |offer| { let _ = t_offer.send(Cmd::OfferArrived { offer, handle: h_offer.clone(), conn, gen }); }),
                        progress: Arc::new(move |got, _| { let _ = t_progress.send(Cmd::Progress { conn, got }); }),
                        claim: Arc::new(move |p| b1.claim(p)),
                        release: Arc::new(move |p| b2.release(p)),
                        handshake_done: Arc::new(move || { s_done.finish(); }),
                        admit: Arc::new(move || c_admit.admit(conn, &pid)),
                        release_at_end: false,
                    };
                    let outcome = run_receive(transport, &me, &peer, folder, mark, &hooks, timings, inbox).await;
                    slot.finish();
                    caps.release(conn);
                    let _ = tx.send(Cmd::ReceiveEnded { conn, outcome, gen, handle, peer_id: pid2 });
                    let _ = tx.send(Cmd::Untrack(conn));
                });
            }
        }
    }

    /// An offer is waiting for a click: its run becomes the receive run now (not when its connection was accepted), and it takes the card only if no other flow's card with buttons is up;
    /// otherwise it is declined, and the user never sees it. An offer of a run that was made before Visible was turned off shows nothing and answers nothing.
    fn offer_arrived(&mut self, offer: Offer, handle: ReceiveHandle, conn: u64, gen: u64) {
        if gen != self.generation() {
            return;
        }
        // Another run still holds the place (its claim is given back after it is cleared), so this is not reached by a run that is over; if it ever is, this one is declined rather than put beside it.
        if self.receive.is_some() {
            handle.respond(false);
            return;
        }
        let ticket = self.gate.begin_receive();
        let card = Card::Offer(offer);
        let flow = card.flow().unwrap_or_default();
        if self.present(Some(card), &flow) {
            self.receive = Some(Receiving { conn, ticket, handle, flow });
        } else {
            self.gate.end_receive();
            handle.respond(false);
        }
    }

    /// Bytes came in. A run has one offer, so the connection stands for it: the tick counts only when it is from the run whose offer is the card on the island.
    fn progressed(&mut self, conn: u64, got: u64) {
        let Some(r) = &self.receive else { return };
        if r.conn != conn || !self.gate.is_receive(r.ticket) {
            return;
        }
        let flow = r.flow.clone();
        match self.card.clone() {
            Some(Card::Offer(o)) | Some(Card::Receiving(o, _)) if self.card.as_ref().and_then(Card::flow).as_deref() == Some(flow.as_str()) => {
                let size = o.size;
                self.present(Some(Card::Receiving(o, got)), &flow);
                if self.pace.due(cards::now_ms(), got >= size) {
                    self.publish(true);
                }
            }
            _ => {}
        }
    }

    /// The user's click on Accept or Decline. The only way an offer is accepted. `shown` is the card the click was meant for (None: the one on the island).
    fn respond_offer(&mut self, accept: bool, shown: Option<ShownView>) {
        let Some(Card::Offer(o)) = self.card.clone() else { return };
        let Some(shown) = parse_shown(&shown) else { return };
        let Some(r) = &self.receive else { return };
        if !self.rules.accepts(shown.as_ref(), cards::now_ms()) || self.card.as_ref().and_then(Card::flow).as_deref() != Some(r.flow.as_str()) {
            return;
        }
        let (handle, flow) = (r.handle.clone(), r.flow.clone());
        // An offer whose run has already ended (expired, withdrawn) is not accepted: the end is on its way and shows what happened.
        if accept {
            if !self.busy.holds(&o.peer_id) {
                return;
            }
            self.present(Some(Card::Receiving(o, 0)), &flow);
        }
        handle.respond(accept);
    }

    fn cancel_receiving(&mut self, shown: Option<ShownView>) {
        let Some(Card::Receiving(..)) = self.card else { return };
        let Some(shown) = parse_shown(&shown) else { return };
        let Some(r) = &self.receive else { return };
        if self.rules.accepts(shown.as_ref(), cards::now_ms()) && self.card.as_ref().and_then(Card::flow).as_deref() == Some(r.flow.as_str()) {
            r.handle.cancel();
        }
    }

    fn receive_ended(&mut self, conn: u64, outcome: TransferOutcome, gen: u64, handle: ReceiveHandle, peer_id: &str) {
        self.log("a transfer ended");
        // The island first, so that no click reaches a run that is over; the transfer place is given back after that.
        if gen == self.generation() {
            if let Some(r) = &self.receive {
                if r.conn == conn {
                    let flow = r.flow.clone();
                    self.receive = None;
                    self.gate.end_receive();
                    let result = match outcome {
                        TransferOutcome::Completed(path) => Some(Card::Result {
                            title: "Received".into(),
                            detail: match &path {
                                Some(p) => format!("Saved as {} in Downloads/NotchMeow.", p.file_name().and_then(|n| n.to_str()).unwrap_or("the file")),
                                None => "Saved.".into(),
                            },
                            file: path,
                        }),
                        TransferOutcome::Declined { .. } | TransferOutcome::Withdrawn => None,
                        TransferOutcome::Expired => Some(Card::Result { title: "Offer expired".into(), detail: "Nobody answered in 2 minutes, so it was declined.".into(), file: None }),
                        TransferOutcome::Cancelled => Some(Card::Result { title: "Transfer cancelled".into(), detail: "Nothing was saved.".into(), file: None }),
                        TransferOutcome::Aborted(_) => Some(Card::Result { title: "Transfer stopped".into(), detail: "The connection ended before the file was complete. Nothing was saved.".into(), file: None }),
                    };
                    self.present(result, &flow);
                }
            }
        }
        if handle.holds_claim() {
            self.busy.release(peer_id);
        }
    }

    /// The OK on a result, or the close of any card: what the user dismissed is answered "no" / "cancel" for its flow, and a result goes.
    fn dismiss(&mut self, shown: Option<ShownView>) {
        match self.card.clone() {
            Some(Card::Offer(_)) => self.respond_offer(false, shown),
            Some(Card::Pair { answered: false, .. }) => self.answer_pair(false, shown),
            Some(Card::Receiving(..)) => self.cancel_receiving(shown),
            Some(Card::Result { .. }) => {
                let Some(s) = parse_shown(&shown) else { return };
                if self.rules.accepts(s.as_ref(), cards::now_ms()) {
                    let owner = self.rules.owner().unwrap_or("").to_string();
                    self.present(None, &owner);
                }
            }
            _ => {}
        }
    }

    // ── Sending ──

    async fn send(&mut self, paths: Vec<PathBuf>, to: &str) {
        if self.sending || self.send_control.is_some() {
            return;
        }
        let Some(peer) = self.paired_peer(to) else {
            self.send_status = Some("That machine is not on the network.".into());
            return;
        };
        let Some(target) = self.seen.get(to).cloned() else {
            self.send_status = Some("That machine is not on the network.".into());
            return;
        };
        let Some(me) = self.identity() else {
            self.send_status = Some("That machine is not on the network.".into());
            return;
        };
        self.sending = true;
        let ctrl = Arc::new(SendControl { peer_id: to.to_string(), cancelled: AtomicBool::new(false), handle: StdMutex::new(None), connecting: Notify::new() });
        self.send_control = Some(ctrl.clone());
        let (gen, tx, cfg) = (self.generation(), self.tx.clone(), self.cfg.clone());
        let conn = self.id();
        tokio::spawn(send_job(tx, ctrl, me, peer, target.addr, paths, gen, conn, cfg));
    }

    /// The Cancel on the shelf's status line. The files that were still to go are not sent, and the send ends within 2 s, whatever phase it is in. A run that exists sends its cancel frame first (the
    /// other side's user then sees "cancelled", not a connection that dropped), and cuts the connection itself only if that frame cannot go out in time. Before there is a run (connecting) there
    /// is nobody to tell, and the connection attempt is dropped now.
    fn cancel_sending(&mut self) {
        if !self.sending {
            return;
        }
        let Some(c) = &self.send_control else { return };
        c.cancelled.store(true, Ordering::SeqCst);
        match c.handle.lock().unwrap().clone() {
            Some(h) => h.cancel(),
            None => {
                c.connecting.notify_waiters();
                self.send_status = Some("Cancelled".into());
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn send_job(tx: mpsc::UnboundedSender<Cmd>, ctrl: Arc<SendControl>, me: Identity, peer: Peer, addr: SocketAddr, paths: Vec<PathBuf>, gen: u64, conn: u64, cfg: Config) {
    let status = |text: String| {
        let _ = tx.send(Cmd::SendStatus(text, gen));
    };
    let mut sent = 0usize;
    for path in paths {
        if ctrl.cancelled.load(Ordering::SeqCst) {
            break;
        }
        let source = match Source::open(&path) {
            Ok(s) => s,
            Err(e) => {
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("That file");
                status(match e {
                    SourceError::NotAFile | SourceError::TooLarge | SourceError::NameTooLong => format!("{name} cannot be sent (a folder, a file over 4 GB, or a name that is too long)."),
                    SourceError::Unreadable => format!("{name} cannot be read."),
                });
                continue;
            }
        };
        let name = source.name.clone();
        status(format!("Waiting for {} to accept {name}", peer.name));
        let transport = tokio::select! {
            t = TcpTransport::connect(addr, cfg.connect_timeout) => t,
            _ = ctrl.connecting.notified() => { status("Cancelled".into()); break; }
        };
        let transport = match transport {
            Ok(t) => t,
            Err(_) => {
                status(if ctrl.cancelled.load(Ordering::SeqCst) { "Cancelled".to_string() } else { format!("Could not reach {}.", peer.name) });
                break;
            }
        };
        // Cancel was clicked while connecting: there is no run to cancel yet, and none is made.
        if ctrl.cancelled.load(Ordering::SeqCst) {
            transport.abort();
            status("Cancelled".into());
            break;
        }
        let _ = tx.send(Cmd::Track { conn, transport: transport.clone(), gen });
        let (handle, inbox) = send_channel(&transport, cfg.send.grace_ms);
        *ctrl.handle.lock().unwrap() = Some(handle);
        let (txp, pname, last) = (tx.clone(), name.clone(), Arc::new(StdMutex::new(-1i64)));
        let peer_name = peer.name.clone();
        let hooks = SendHooks {
            progress: Arc::new(move |done, total| {
                let pct = if total == 0 { 100 } else { (done * 100 / total).min(100) as i64 };
                let mut l = last.lock().unwrap();
                if *l != pct {
                    *l = pct;
                    let _ = txp.send(Cmd::SendStatus(format!("Sending {pname} to {peer_name}, {pct} %"), gen));
                }
            }),
        };
        let outcome = run_send(transport, &me, &peer, source, &hooks, cfg.send, inbox).await;
        *ctrl.handle.lock().unwrap() = None;
        let _ = tx.send(Cmd::Untrack(conn));
        let cancelled = ctrl.cancelled.load(Ordering::SeqCst);
        match outcome {
            // The protocol has no receipt: all the bytes and the end marker went out, which is all this side can say.
            TransferOutcome::Completed(_) => {
                sent += 1;
                status(format!("Finished sending {name} to {}", peer.name));
            }
            TransferOutcome::Declined { reason } => status(match reason {
                1 => format!("{} did not answer in time", peer.name),
                2 => format!("{} is receiving something else right now", peer.name),
                3 => format!("{name} is too large"),
                _ => format!("{} declined {name}", peer.name),
            }),
            TransferOutcome::Expired => {
                status(format!("{} did not answer in time", peer.name));
                ctrl.cancelled.store(true, Ordering::SeqCst);
            }
            TransferOutcome::Withdrawn | TransferOutcome::Cancelled => {
                status("Cancelled".into());
                ctrl.cancelled.store(true, Ordering::SeqCst);
            }
            TransferOutcome::Aborted(_) => status(if cancelled { "Cancelled".to_string() } else { format!("The connection to {} ended", peer.name) }),
        }
    }
    if sent > 1 && !ctrl.cancelled.load(Ordering::SeqCst) {
        status(format!("Finished sending {sent} files to {}", peer.name));
    }
    let _ = tx.send(Cmd::SendDone(gen));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::discovery::OnResults;
    use crate::link::keystore::MemoryStore;
    use sha2::{Digest, Sha256};
    use std::sync::atomic::AtomicUsize;

    #[derive(Default)]
    struct FakeDiscovery {
        advert: StdMutex<Option<(String, String, u16)>>,
        adverts: AtomicUsize,
        browses: AtomicUsize,
        results: StdMutex<Option<OnResults>>,
    }

    impl Discovery for FakeDiscovery {
        fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
            self.adverts.fetch_add(1, Ordering::SeqCst);
            *self.advert.lock().unwrap() = Some((id.into(), name.into(), port));
            Ok(())
        }
        fn stop_advertising(&self) {
            *self.advert.lock().unwrap() = None;
        }
        /// Like `Mdns`: a search that is running is left alone (its first callback stays), one that has ended is made again.
        fn browse(&self, _own: &str, on: OnResults) -> Result<(), String> {
            self.browses.fetch_add(1, Ordering::SeqCst);
            let mut r = self.results.lock().unwrap();
            if r.is_none() {
                *r = Some(on);
            }
            Ok(())
        }
        fn stop_browsing(&self) {
            *self.results.lock().unwrap() = None;
        }
    }

    impl FakeDiscovery {
        /// The daemon was replaced: the search is over and nobody was told (`Mdns` does this).
        fn end_silently(&self) {
            *self.results.lock().unwrap() = None;
        }
        fn show(&self, found: Vec<Found>) {
            if let Some(cb) = &*self.results.lock().unwrap() {
                cb(found);
            }
        }
    }

    #[derive(Default)]
    struct Capture {
        snaps: StdMutex<Vec<Snapshot>>,
        logs: StdMutex<Vec<String>>,
    }

    impl Emit for Capture {
        fn snapshot(&self, s: &Snapshot) {
            self.snaps.lock().unwrap().push(s.clone());
        }
        fn log(&self, line: &'static str) {
            self.logs.lock().unwrap().push(line.to_string());
        }
    }

    struct Node {
        svc: Service,
        disc: Arc<FakeDiscovery>,
        cap: Arc<Capture>,
        folder: PathBuf,
        dir: PathBuf,
        store: Arc<MemoryStore>,
    }

    fn temp(tag: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let d = std::env::temp_dir().join(format!("notchmeow-svc-{tag}-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn node(name: &str) -> Node {
        node_in(name, |dir| dir.join("Downloads").join("NotchMeow"))
    }

    fn node_in(name: &str, folder: impl FnOnce(&std::path::Path) -> PathBuf) -> Node {
        let dir = temp("node");
        let folder = folder(&dir);
        let mut cfg = Config::app(dir.join("link.json"), folder.clone(), name.to_string());
        cfg.bind = "127.0.0.1:0".parse().unwrap();
        let (disc, cap) = (Arc::new(FakeDiscovery::default()), Arc::new(Capture::default()));
        let store = Arc::new(MemoryStore::default());
        let shared: Arc<dyn SecretStore> = store.clone();
        let deps = Deps { keystore: Arc::new(Keystore::new(shared)), discovery: disc.clone(), emit: cap.clone() };
        let svc = Service::spawn(|f| { tokio::spawn(f); }, cfg, deps);
        svc.start();
        Node { svc, disc, cap, folder, dir, store }
    }

    async fn until(what: &str, f: impl Fn() -> bool) {
        for _ in 0..1500 {
            if f() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(4)).await;
        }
        panic!("never happened: {what}");
    }

    fn last(n: &Node) -> Option<Snapshot> {
        n.cap.snaps.lock().unwrap().last().cloned()
    }

    async fn wait_snap(n: &Node, what: &str, f: impl Fn(&Snapshot) -> bool) {
        until(what, || last(n).is_some_and(|s| f(&s))).await;
    }

    fn card_kind(n: &Node) -> Option<&'static str> {
        last(n).and_then(|s| s.card).map(|c| c.kind)
    }

    /// Both are visible and listening; A is on the shelf, has found B and lists it. B's id.
    async fn meet(a: &Node, b: &Node) -> String {
        a.svc.set_visible(true);
        b.svc.set_visible(true);
        wait_snap(a, "A listens", |s| s.listening).await;
        wait_snap(b, "B listens", |s| s.listening).await;
        a.svc.set_shelf_open(true);
        let (id, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        until("A browses", || a.disc.results.lock().unwrap().is_some()).await;
        a.disc.show(vec![Found { advert: Advert { id: id.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(a, "A lists B", |s| s.rows.iter().any(|r| r.id == id)).await;
        id
    }

    /// A pairs with B as two users agreeing would: both screens show the code, both click "They match", both close the result.
    async fn pair_up(a: &Node, b: &Node) {
        let id = meet(a, b).await;
        b.svc.set_devices_open(true);
        a.svc.pair(id);
        wait_snap(a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        let (ca, cb) = (last(a).unwrap().card.unwrap().code.unwrap(), last(b).unwrap().card.unwrap().code.unwrap());
        assert_eq!(ca, cb, "both screens show the same six digits");
        tokio::time::sleep(Duration::from_millis(750)).await; // the quiet period of a card that has just appeared
        a.svc.answer_pair(true, None);
        b.svc.answer_pair(true, None);
        wait_snap(a, "A paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Paired"))).await;
        wait_snap(b, "B paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Paired"))).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.dismiss(None);
        b.svc.dismiss(None);
        wait_snap(a, "A clear", |s| s.card.is_none()).await;
        wait_snap(b, "B clear", |s| s.card.is_none()).await;
    }

    /// B is visible, A has found it and both are paired, as two users agreeing would leave them.
    async fn paired() -> (Node, Node) {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        pair_up(&a, &b).await;
        (a, b)
    }

    fn id_of(n: &Node) -> String {
        n.disc.advert.lock().unwrap().clone().unwrap().0
    }

    fn sha(b: &[u8]) -> String {
        hex(&Sha256::digest(b))
    }

    /// The one sample file that Rust and the page both read (windows/scripts/link-tests/snapshot-samples.json; the page's side is model.test.mjs): what is serialized here is what the page keeps whole.
    #[test]
    fn the_snapshot_the_page_gets_is_the_sample_file() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../scripts/link-tests/snapshot-samples.json");
        let samples: Vec<serde_json::Value> = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let blank = |folder: &str| Snapshot { visible: true, name: "Desk PC".into(), listening: true, problem: None, note: None, rows: vec![], card: None, send_status: None, sending: false, folder: folder.into() };
        let card = |kind: &'static str, key: &str| CardView { kind, key: key.into(), code: None, peer: None, answered: None, name: None, size: None, received: None, title: None, detail: None, can_reveal: None };
        let row = |id: &str, name: &str, state: &'static str| RowView { id: id.repeat(16), name: name.into(), state };
        let built = vec![
            Snapshot { visible: false, listening: false, ..blank("C:\\Users\\Sam\\Downloads\\NotchMeow") },
            Snapshot {
                note: Some("Wait 30 seconds before trying again.".into()),
                rows: vec![row("a1", "Sam's MacBook Pro", "pairedOnline"), row("b2", "Old netbook", "pairedOffline"), row("c3", "Studio laptop", "available")],
                send_status: Some("Sending report.pdf to Sam's MacBook Pro, 45 %".into()),
                sending: true,
                ..blank("/home/sam/Downloads/NotchMeow")
            },
            Snapshot { problem: Some(ADVERT_PROBLEM.into()), card: Some(CardView { code: Some("483291".into()), peer: Some("Sam's MacBook Pro".into()), answered: Some(false), ..card("pair", "483291|Sam's MacBook Pro") }), ..blank("") },
            Snapshot { card: Some(CardView { name: Some("Quarterly report.pdf".into()), size: Some(2_400_000), peer: Some("Sam's MacBook Pro".into()), ..card("offer", &format!("{}|0102", "a1".repeat(16))) }), ..blank("") },
            Snapshot {
                card: Some(CardView { name: Some("Quarterly report.pdf".into()), size: Some(2_400_000), received: Some(1_080_000), peer: Some("Sam's MacBook Pro".into()), ..card("receiving", &format!("{}|0102", "a1".repeat(16))) }),
                ..blank("")
            },
            Snapshot {
                card: Some(CardView {
                    title: Some("Received".into()),
                    detail: Some("Saved as Quarterly report.pdf in Downloads/NotchMeow.".into()),
                    can_reveal: Some(true),
                    ..card("result", "Received|Saved as Quarterly report.pdf in Downloads/NotchMeow.")
                }),
                ..blank("")
            },
        ];
        assert_eq!(built.len(), samples.len());
        for (b, s) in built.iter().zip(&samples) {
            assert_eq!(serde_json::to_value(b).unwrap(), s["snapshot"], "{}", s["name"]);
        }
    }

    #[tokio::test]
    async fn nothing_listens_and_nothing_is_announced_until_visible_is_turned_on() {
        let n = node("Desk PC");
        let s = n.svc.snapshot().await.unwrap();
        assert!(!s.visible && !s.listening);
        assert!(n.disc.advert.lock().unwrap().is_none(), "no advert");
        assert!(n.disc.results.lock().unwrap().is_none(), "no browser");
        n.svc.set_devices_open(true);
        let s = n.svc.snapshot().await.unwrap();
        assert!(!s.listening && n.disc.results.lock().unwrap().is_none(), "opening Devices does not start anything while Visible is off");
        assert!(n.cap.logs.lock().unwrap().is_empty());
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        let (id, name, port) = n.disc.advert.lock().unwrap().clone().unwrap();
        assert!(crate::link::bytes::is_id_hex(&id) && name == "Desk PC" && port > 0);
        assert!(n.disc.results.lock().unwrap().is_some(), "Devices was open: turning Visible on starts the search");
        n.svc.set_visible(false);
        wait_snap(&n, "stopped", |s| !s.listening).await;
        assert!(n.disc.advert.lock().unwrap().is_none(), "the advert goes with the listener");
        assert!(n.disc.results.lock().unwrap().is_none(), "and the browser");
        let saved = settings::load(&n.dir.join("link.json"), "x");
        assert!(!saved.visible, "off is saved");
    }

    #[tokio::test]
    async fn the_search_runs_while_devices_or_the_shelf_is_on_screen_and_stops_when_neither_is() {
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        assert!(n.disc.results.lock().unwrap().is_none(), "visible, but nobody is looking");
        n.svc.set_devices_open(true);
        n.svc.set_devices_open(true); // saying it twice changes nothing
        n.svc.set_shelf_open(true);
        until("browsing", || n.disc.results.lock().unwrap().is_some()).await;
        n.svc.set_devices_open(false);
        n.svc.set_devices_open(false);
        let _ = n.svc.snapshot().await;
        assert!(n.disc.results.lock().unwrap().is_some(), "the shelf is still open");
        n.svc.set_shelf_open(false);
        let _ = n.svc.snapshot().await;
        assert!(n.disc.results.lock().unwrap().is_none(), "nobody looks: the browser is gone");
    }

    #[tokio::test]
    async fn a_name_a_card_would_refuse_is_not_taken_and_a_new_name_is_announced_again() {
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        assert!(!n.svc.set_device_name(" padded".into()).await);
        assert!(!n.svc.set_device_name("a\u{202e}b".into()).await);
        assert!(n.svc.set_device_name("Studio PC".into()).await);
        assert_eq!(n.disc.advert.lock().unwrap().clone().unwrap().1, "Studio PC");
        assert_eq!(n.disc.adverts.load(Ordering::SeqCst), 2);
        assert!(last(&n).unwrap().listening, "the listener was not restarted");
    }

    #[tokio::test]
    async fn two_machines_pair_with_matching_codes_and_send_a_file_that_arrives_whole() {
        let (a, b) = paired().await;
        let ids = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        assert_eq!(last(&a).unwrap().rows[0].state, "pairedOnline");
        assert_eq!(last(&b).unwrap().rows[0].id, ids.0, "B knows A too");
        let src = temp("src");
        let data: Vec<u8> = (0..150_000).map(|i| (i % 253) as u8).collect();
        let file = src.join("report.pdf");
        std::fs::write(&file, &data).unwrap();
        a.svc.send(vec![file], ids.1.clone());
        wait_snap(&b, "the offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        let card = last(&b).unwrap().card.unwrap();
        assert_eq!((card.name.as_deref(), card.size, card.peer.as_deref()), (Some("report.pdf"), Some(150_000), Some("Sam's MacBook Pro")));
        assert!(!b.folder.exists() || std::fs::read_dir(&b.folder).unwrap().next().is_none(), "nothing is written before the click");
        // A click inside the 700 ms quiet period does nothing; later it accepts.
        b.svc.respond_offer(true, None);
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(card_kind(&b), Some("offer"), "too early");
        tokio::time::sleep(Duration::from_millis(700)).await;
        b.svc.respond_offer(true, Some(ShownView { kind: "offer".into(), key: card.key.clone() }));
        wait_snap(&b, "received", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Received"))).await;
        let saved = b.folder.join("report.pdf");
        assert_eq!(sha(&std::fs::read(&saved).unwrap()), sha(&data));
        assert_eq!(b.svc.result_file().await, Some(saved));
        wait_snap(&a, "A's line", |s| s.send_status.as_deref().is_some_and(|t| t.starts_with("Finished sending report.pdf to Desk PC"))).await;
        wait_snap(&a, "A done", |s| !s.sending).await;
        let logs = b.cap.logs.lock().unwrap().join("|");
        assert!(!logs.contains("report") && !logs.contains("Desk") && !logs.contains("127.0.0.1"), "the log holds fixed sentences only: {logs}");
    }

    #[tokio::test]
    async fn a_click_meant_for_another_card_does_nothing() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        b.svc.respond_offer(true, Some(ShownView { kind: "offer".into(), key: "someone else|t9".into() }));
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(card_kind(&b), Some("offer"), "a click for a card that is not the one shown does nothing");
        b.svc.respond_offer(false, None);
        wait_snap(&b, "declined", |s| s.card.is_none()).await;
        wait_snap(&a, "A hears no", |s| s.send_status.as_deref() == Some("Desk PC declined a.bin")).await;
        assert!(b.folder.read_dir().map(|mut d| d.next().is_none()).unwrap_or(true));
    }

    #[tokio::test]
    async fn an_incoming_pairing_outside_the_gate_is_refused_silently() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        a.svc.set_visible(true);
        b.svc.set_visible(true);
        wait_snap(&a, "A listens", |s| s.listening).await;
        wait_snap(&b, "B listens", |s| s.listening).await;
        a.svc.set_shelf_open(true);
        until("A browses", || a.disc.results.lock().unwrap().is_some()).await;
        let (id, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        a.disc.show(vec![Found { advert: Advert { id: id.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(&a, "A lists B", |s| !s.rows.is_empty()).await;
        a.svc.pair(id);
        wait_snap(&a, "A's note", |s| s.note.as_deref() == Some("The pairing did not go through.")).await;
        assert!(last(&b).unwrap().card.is_none(), "no card on B");
        assert!(b.cap.logs.lock().unwrap().iter().all(|l| l != "a pairing ended"), "B did not run a pairing at all");
    }

    #[tokio::test]
    async fn turning_visible_off_while_an_offer_waits_clears_the_card_and_cuts_the_connection() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        b.svc.set_visible(false);
        wait_snap(&b, "card gone", |s| s.card.is_none() && !s.listening).await;
        wait_snap(&a, "A sees the connection end", |s| s.send_status.as_deref() == Some("The connection to Desk PC ended")).await;
    }

    #[tokio::test]
    async fn forgetting_a_machine_withdraws_its_waiting_offer() {
        let (a, b) = paired().await;
        let (aid, bid) = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        b.svc.forget(aid);
        wait_snap(&b, "card gone", |s| s.card.is_none() && s.rows.is_empty()).await;
    }

    #[tokio::test]
    async fn forgetting_a_machine_cancels_a_send_to_it_and_the_files_still_to_go() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        for n in ["1.bin", "2.bin", "3.bin"] {
            std::fs::write(src.join(n), vec![1u8; 1000]).unwrap();
        }
        a.svc.send(vec![src.join("1.bin"), src.join("2.bin"), src.join("3.bin")], bid.clone());
        wait_snap(&b, "the first offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        a.svc.forget(bid);
        wait_snap(&a, "the send is cancelled", |s| s.send_status.as_deref() == Some("Cancelled") && !s.sending).await;
        wait_snap(&b, "B's card goes", |s| s.card.as_ref().map_or(true, |c| c.kind == "result")).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        let offers = b.cap.snaps.lock().unwrap().iter().filter(|s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).map(|s| s.card.as_ref().unwrap().name.clone()).collect::<std::collections::HashSet<_>>();
        assert_eq!(offers.len(), 1, "only the first file was ever offered: {offers:?}");
    }

    #[tokio::test]
    async fn a_transfer_from_a_machine_that_is_not_paired_is_closed_without_an_answer() {
        let (a, b) = paired().await;
        let (aid, bid) = (a.disc.advert.lock().unwrap().clone().unwrap().0, b.disc.advert.lock().unwrap().clone().unwrap().0);
        b.svc.forget(aid);
        wait_snap(&b, "forgotten", |s| s.rows.is_empty()).await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid);
        wait_snap(&a, "A's line", |s| s.send_status.as_deref() == Some("The connection to Desk PC ended")).await;
        assert!(last(&b).unwrap().card.is_none());
    }

    #[tokio::test]
    async fn cancelling_a_send_ends_it_and_the_files_still_to_go_are_not_sent() {
        let (a, b) = paired().await;
        let bid = b.disc.advert.lock().unwrap().clone().unwrap().0;
        let src = temp("src");
        for n in ["1.bin", "2.bin", "3.bin"] {
            std::fs::write(src.join(n), vec![1u8; 1000]).unwrap();
        }
        a.svc.send(vec![src.join("1.bin"), src.join("2.bin"), src.join("3.bin")], bid);
        wait_snap(&b, "the first offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        a.svc.cancel_sending();
        wait_snap(&a, "cancelled", |s| s.send_status.as_deref() == Some("Cancelled") && !s.sending).await;
        wait_snap(&b, "B's card goes", |s| s.card.as_ref().map_or(true, |c| c.kind == "result")).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        let offers = b.cap.snaps.lock().unwrap().iter().filter(|s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).map(|s| s.card.as_ref().unwrap().name.clone()).collect::<std::collections::HashSet<_>>();
        assert_eq!(offers.len(), 1, "only the first file was ever offered: {offers:?}");
    }

    // ── What the controller's reviews of Tasks 2 to 12 added to the brief ──

    /// The listener is IPv4 only (the advert is too) and a new connection has the contract's 10 seconds for its handshake.
    #[test]
    fn the_app_listens_on_ipv4_only_and_gives_a_new_connection_ten_seconds_for_its_handshake() {
        let cfg = Config::app(PathBuf::from("link.json"), PathBuf::from("NotchMeow"), "Desk PC".into());
        assert_eq!(cfg.bind, "0.0.0.0:0".parse::<SocketAddr>().unwrap());
        assert!(cfg.bind.is_ipv4());
        assert_eq!(cfg.handshake, Duration::from_secs(HANDSHAKE_SECONDS));
        assert_eq!(HANDSHAKE_SECONDS, 10);
    }

    #[test]
    fn a_name_is_announced_only_if_a_card_would_show_it() {
        assert!(advertisable("Desk PC") && advertisable("Sam's MacBook Pro"));
        for bad in ["", " padded", "padded ", "a\u{202e}b", "a\nb", &"x".repeat(64)] {
            assert!(!advertisable(bad), "{bad:?}");
        }
        // And whatever one character of a computer's name makes of the default name, it is a name that passes.
        for c in (0..0x11_0000u32).filter_map(char::from_u32) {
            assert!(advertisable(&settings::default_name(&format!("a{c}b"))), "U+{:04X}", c as u32);
        }
    }

    #[test]
    fn what_the_page_is_given_prints_as_a_fixed_label() {
        let key = format!("{}|0102", "5e".repeat(16));
        let card = CardView { kind: "offer", key: key.clone(), code: Some("483291".into()), peer: Some("Sam's MacBook Pro".into()), answered: None, name: Some("Quarterly report.pdf".into()), size: Some(2_400_000), received: None, title: None, detail: Some("Saved in C:\\Users\\Sam".into()), can_reveal: None };
        let row = RowView { id: "5e".repeat(16), name: "Studio laptop".into(), state: "available" };
        let snap = Snapshot { visible: true, name: "Desk PC".into(), listening: true, problem: None, note: Some("a note".into()), rows: vec![row.clone()], card: Some(card.clone()), send_status: Some("Sending report.pdf".into()), sending: true, folder: "C:\\Users\\Sam\\Downloads".into() };
        let offer = Offer { transfer_id: "0102".into(), name: "Quarterly report.pdf".into(), size: 1, peer_id: "5e".repeat(16), peer_name: "Sam's MacBook Pro".into() };
        let result = Card::Result { title: "Received".into(), detail: "Saved as Quarterly report.pdf".into(), file: Some(PathBuf::from("/home/sam/Downloads/NotchMeow/Quarterly report.pdf")) };
        let text = format!("{snap:?} {card:?} {row:?} {:?} {:?} {result:?}", ShownView { kind: "offer".into(), key }, Card::Offer(offer));
        for secret in ["5e5e", "Sam", "Desk PC", "Studio", "report", "483291", "Users", "a note", "home"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
    }

    #[test]
    fn progress_is_let_through_every_100_ms_and_at_the_end() {
        let mut pace = Pace::default();
        assert!(pace.due(5_000, false), "the first tick");
        assert!(!pace.due(5_050, false) && !pace.due(5_099, false));
        assert!(pace.due(5_100, false));
        assert!(!pace.due(5_110, false));
        assert!(pace.due(5_111, true), "the end always");
    }

    #[tokio::test]
    async fn a_big_file_moves_the_progress_bar_without_flooding_the_page() {
        let (a, b) = paired().await;
        let size = 3_000_000usize;
        let src = temp("src");
        std::fs::write(src.join("big.bin"), (0..size).map(|i| (i % 251) as u8).collect::<Vec<u8>>()).unwrap();
        a.svc.send(vec![src.join("big.bin")], id_of(&b));
        wait_snap(&b, "the offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        b.svc.respond_offer(true, None);
        wait_snap(&b, "received", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Received"))).await;
        let ticks: Vec<u64> = b.cap.snaps.lock().unwrap().iter().filter_map(|s| s.card.as_ref().filter(|c| c.kind == "receiving").and_then(|c| c.received)).collect();
        let chunks = size / 32_768;
        assert!(ticks.len() < chunks / 2, "{} snapshots for {chunks} chunks", ticks.len());
        assert_eq!(ticks.last().copied(), Some(size as u64), "the last tick is the whole file");
    }

    /// Listener::stop bounds the connections that wait for their first record by the 10 s watchdog; the service cuts them at once.
    #[tokio::test]
    async fn a_connection_that_has_not_said_hello_is_cut_when_visible_is_turned_off() {
        use tokio::io::AsyncReadExt;
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        let port = n.disc.advert.lock().unwrap().clone().unwrap().2;
        let mut quiet = tokio::net::TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await; // the listener has taken it in and waits for its first record
        n.svc.set_visible(false);
        wait_snap(&n, "stopped", |s| !s.listening).await;
        let mut byte = [0u8; 1];
        let read = tokio::time::timeout(Duration::from_secs(2), quiet.read(&mut byte)).await;
        assert!(matches!(read, Ok(Ok(0)) | Ok(Err(_))), "cut at once, not after the listener's 10 s: {read:?}");
    }

    #[tokio::test]
    async fn turning_visible_off_while_a_pairing_code_is_up_clears_the_card_on_both_sides() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        let id = meet(&a, &b).await;
        b.svc.set_devices_open(true);
        a.svc.pair(id);
        wait_snap(&a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(&b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        b.svc.set_visible(false);
        wait_snap(&b, "B clear", |s| s.card.is_none() && !s.listening).await;
        wait_snap(&a, "A clear", |s| s.card.is_none() && s.note.as_deref() == Some("The pairing did not go through.")).await;
    }

    #[tokio::test]
    async fn the_other_user_saying_no_ends_the_pairing_the_code_goes_and_no_key_is_kept() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        let id = meet(&a, &b).await;
        b.svc.set_devices_open(true);
        a.svc.pair(id);
        wait_snap(&a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(&b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.answer_pair(true, None);
        b.svc.answer_pair(false, None);
        wait_snap(&a, "A: not paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Not paired") && c.code.is_none())).await;
        wait_snap(&b, "B: card gone", |s| s.card.is_none()).await;
        assert!(Keystore::new(a.store.clone()).paired_machines(false).unwrap().is_empty(), "nothing was stored");
        assert!(Keystore::new(b.store.clone()).paired_machines(false).unwrap().is_empty());
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.dismiss(None);
        wait_snap(&a, "A clear", |s| s.card.is_none()).await;
    }

    #[tokio::test]
    async fn closing_the_pairing_card_ends_the_pairing_on_both_sides() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        let id = meet(&a, &b).await;
        b.svc.set_devices_open(true);
        a.svc.pair(id);
        wait_snap(&a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(&b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.dismiss(None);
        wait_snap(&a, "A clear", |s| s.card.is_none()).await;
        wait_snap(&b, "B: not paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Not paired") && c.code.is_none())).await;
        assert!(Keystore::new(a.store.clone()).paired_machines(false).unwrap().is_empty());
    }

    /// `Responder` and the machines return "store" without looking at the paired map again; the keystore does, when it writes.
    #[tokio::test]
    async fn a_key_is_stored_only_if_the_paired_map_still_agrees_when_it_is_written() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        let bid = meet(&a, &b).await;
        b.svc.set_devices_open(true);
        a.svc.pair(bid.clone());
        wait_snap(&a, "A's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        wait_snap(&b, "B's code", |s| s.card.as_ref().is_some_and(|c| c.kind == "pair")).await;
        // While the code is up (a pairing takes up to two minutes) another pairing stored a different key under B's id: the map this pairing started with does not know it.
        let rival = Peer { id: bid.clone(), name: "Desk PC".into(), key: "ab".repeat(32), at: 0 };
        Keystore::new(a.store.clone()).add(&rival, &id_of(&a)).unwrap();
        tokio::time::sleep(Duration::from_millis(750)).await;
        a.svc.answer_pair(true, None);
        b.svc.answer_pair(true, None);
        wait_snap(&a, "A refuses", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Not paired"))).await;
        wait_snap(&b, "B paired", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Paired"))).await;
        assert_eq!(Keystore::new(a.store.clone()).paired_machines(true).unwrap()[&bid].key, "ab".repeat(32), "the key that was there is not replaced");
    }

    /// The gate counts appearances, so the service says "open" and "closed" as a state: two openings and one close leave Devices shut.
    #[tokio::test]
    async fn devices_on_screen_is_a_state_so_opening_it_twice_and_closing_it_once_closes_the_gate() {
        let (a, b) = (node("Sam's MacBook Pro"), node("Desk PC"));
        let id = meet(&a, &b).await;
        b.svc.set_devices_open(true);
        b.svc.set_devices_open(true);
        b.svc.set_devices_open(false);
        let _ = b.svc.snapshot().await;
        a.svc.pair(id);
        wait_snap(&a, "A's note", |s| s.note.as_deref() == Some("The pairing did not go through.")).await;
        assert!(last(&b).unwrap().card.is_none(), "no card on B");
        assert!(b.cap.logs.lock().unwrap().iter().all(|l| l != "a pairing ended"), "B did not run a pairing at all");
    }

    /// Task 12's browser may end a search by itself when its daemon is replaced: the service starts it again when the machines are looked at again.
    #[tokio::test]
    async fn a_search_that_ended_by_itself_is_started_again_when_devices_or_the_shelf_comes_on_screen_or_visible_is_toggled() {
        let n = node("Desk PC");
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        n.svc.set_shelf_open(true);
        until("browsing", || n.disc.results.lock().unwrap().is_some()).await;
        n.disc.end_silently();
        n.svc.set_devices_open(true);
        until("browsing again", || n.disc.results.lock().unwrap().is_some()).await;
        let id = "ab".repeat(16);
        n.disc.show(vec![Found { advert: Advert { id: id.clone(), name: "Old netbook".into() }, addr: "127.0.0.1:9".parse().unwrap() }]);
        wait_snap(&n, "lists it", |s| s.rows.iter().any(|r| r.id == id)).await;
        n.disc.end_silently();
        n.svc.set_devices_open(true); // the page says it again
        until("browsing after Devices said so", || n.disc.results.lock().unwrap().is_some()).await;
        n.disc.end_silently();
        n.svc.set_shelf_open(true); // and so does the shelf: the machines are looked at
        until("browsing after the shelf said so", || n.disc.results.lock().unwrap().is_some()).await;
        n.disc.end_silently();
        n.svc.set_visible(false);
        n.svc.set_visible(true);
        until("browsing after the toggle", || n.disc.results.lock().unwrap().is_some()).await;
        assert!(n.disc.browses.load(Ordering::SeqCst) >= 4);
    }

    #[tokio::test]
    async fn a_late_event_of_a_stopped_conversation_acts_on_nothing() {
        let n = node("Desk PC");
        let offer = || Offer { transfer_id: "0102".into(), name: "report.pdf".into(), size: 10, peer_id: "a1".repeat(16), peer_name: "Sam's MacBook Pro".into() };
        let (handle, _inbox) = receive_channel();
        // The control: an offer of the current generation takes the card, so the commands below do reach the service.
        n.svc.post(Cmd::OfferArrived { offer: offer(), handle: handle.clone(), conn: 7, gen: 0 });
        wait_snap(&n, "the control's card", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        n.svc.set_visible(false);
        wait_snap(&n, "stopped", |s| !s.listening && s.card.is_none()).await;
        n.svc.post(Cmd::OfferArrived { offer: offer(), handle, conn: 8, gen: 0 });
        n.svc.post(Cmd::PairCode { ticket: Ticket { generation: 0, serial: 1 }, code: "483291".into(), name: "Sam's MacBook Pro".into() });
        n.svc.post(Cmd::SendStatus("Sending report.pdf".into(), 0));
        n.svc.post(Cmd::Progress { conn: 7, got: 5 });
        let s = n.svc.snapshot().await.unwrap();
        assert!(s.card.is_none() && s.send_status.is_none(), "a late event of the first generation changed what the page shows");
    }

    /// One transfer for the whole machine: while A's offer waits for a click, C's is declined as busy and B's card is still A's.
    #[tokio::test]
    async fn the_machine_takes_one_transfer_at_a_time_and_the_second_sender_is_told_it_is_busy() {
        let (a, b, c) = (node("Sam's MacBook Pro"), node("Desk PC"), node("Studio laptop"));
        pair_up(&a, &b).await;
        pair_up(&b, &c).await;
        let bid = id_of(&b);
        c.svc.set_shelf_open(true);
        until("C browses", || c.disc.results.lock().unwrap().is_some()).await;
        let (_, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        c.disc.show(vec![Found { advert: Advert { id: bid.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(&c, "C lists B", |s| s.rows.iter().any(|r| r.id == bid && r.state == "pairedOnline")).await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        std::fs::write(src.join("c.bin"), vec![2u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid.clone());
        wait_snap(&b, "A's offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer" && c.name.as_deref() == Some("a.bin"))).await;
        c.svc.send(vec![src.join("c.bin")], bid);
        wait_snap(&c, "C is told", |s| s.send_status.as_deref() == Some("Desk PC is receiving something else right now")).await;
        let card = last(&b).unwrap().card.unwrap();
        assert_eq!((card.kind, card.name.as_deref()), ("offer", Some("a.bin")), "the card is still A's offer");
        assert!(b.cap.snaps.lock().unwrap().iter().all(|s| s.card.as_ref().map_or(true, |c| c.name.as_deref() != Some("c.bin"))), "C's file was never shown");
    }

    /// The island has one card: a pairing from another machine never lands in front of an offer the user is about to click.
    #[tokio::test]
    async fn a_pairing_code_from_another_machine_never_replaces_a_card_with_buttons() {
        let (b, a) = (node("Desk PC"), node("Sam's MacBook Pro"));
        pair_up(&b, &a).await; // B asked A, so B's own gap between incoming pairings is untouched
        let c = node("Studio laptop");
        let bid = meet(&c, &b).await;
        b.svc.set_devices_open(true); // the gate is open: only the card keeps C out
        let (_, name, port) = b.disc.advert.lock().unwrap().clone().unwrap();
        until("A browses", || a.disc.results.lock().unwrap().is_some()).await; // A was only asked: Devices is open on it, so it looks
        a.disc.show(vec![Found { advert: Advert { id: bid.clone(), name }, addr: format!("127.0.0.1:{port}").parse().unwrap() }]);
        wait_snap(&a, "A lists B", |s| s.rows.iter().any(|r| r.id == bid && r.state == "pairedOnline")).await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], bid.clone());
        wait_snap(&b, "A's offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        let before = b.cap.snaps.lock().unwrap().len();
        c.svc.pair(bid);
        wait_snap(&c, "C's note", |s| s.note.as_deref() == Some("The pairing did not go through.")).await;
        let card = last(&b).unwrap().card.unwrap();
        assert_eq!((card.kind, card.name.as_deref()), ("offer", Some("a.bin")));
        assert!(b.cap.snaps.lock().unwrap()[before..].iter().all(|s| s.card.as_ref().map_or(true, |c| c.kind != "pair")), "no code showed on B");
    }

    /// A drive that cannot be written (on Windows also one that cannot hold the mark of the web) ends as one fixed text and keeps nothing.
    #[tokio::test]
    async fn a_folder_that_cannot_be_written_ends_as_transfer_stopped_and_keeps_nothing() {
        let a = node("Sam's MacBook Pro");
        let b = node_in("Desk PC", |dir| {
            let blocker = dir.join("blocker");
            std::fs::write(&blocker, b"x").unwrap();
            blocker.join("NotchMeow")
        });
        pair_up(&a, &b).await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], id_of(&b));
        wait_snap(&b, "the offer", |s| s.card.as_ref().is_some_and(|c| c.kind == "offer")).await;
        tokio::time::sleep(Duration::from_millis(750)).await;
        b.svc.respond_offer(true, None);
        wait_snap(&b, "stopped", |s| s.card.as_ref().is_some_and(|c| c.title.as_deref() == Some("Transfer stopped") && c.can_reveal == Some(false))).await;
        assert_eq!(std::fs::read(b.folder.parent().unwrap()).unwrap(), b"x", "what was there is untouched");
    }

    #[tokio::test]
    async fn turning_visible_off_while_sending_ends_the_send_and_leaves_no_status() {
        let (a, b) = paired().await;
        let src = temp("src");
        std::fs::write(src.join("a.bin"), vec![1u8; 1000]).unwrap();
        a.svc.send(vec![src.join("a.bin")], id_of(&b));
        wait_snap(&b, "the offer", |s| s.card.is_some()).await;
        a.svc.set_visible(false);
        wait_snap(&a, "A stopped", |s| !s.listening && !s.sending && s.send_status.is_none()).await;
        wait_snap(&b, "B's card goes", |s| s.card.as_ref().map_or(true, |c| c.kind == "result")).await;
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(last(&a).unwrap().send_status.is_none(), "a late line of the stopped send is not shown");
    }

    // ── Fix round 1 ──

    /// A launch with Visible off, and Devices or the shelf looked at, must not read, make or write the device id or the static key, and must show no store problem.
    #[tokio::test]
    async fn with_visible_off_nothing_is_made_or_written_even_when_devices_and_the_shelf_come_on_screen() {
        let n = node("Desk PC");
        let _ = n.svc.snapshot().await; // the launch (Start) has been handled
        n.svc.set_devices_open(true);
        n.svc.set_shelf_open(true);
        n.svc.set_devices_open(false);
        n.svc.set_shelf_open(false);
        n.svc.set_shelf_open(true);
        let s = n.svc.snapshot().await.unwrap();
        assert!(!s.visible && !s.listening && s.problem.is_none(), "no problem line");
        assert!(n.store.accounts().is_empty(), "nothing was made or written: {:?}", n.store.accounts());
    }

    /// The credential store cannot be read (no Secret Service): a machine that is not visible says nothing about it until Devices is looked at or Visible is turned on.
    #[tokio::test]
    async fn a_launch_with_visible_off_shows_no_problem_even_when_the_store_cannot_be_read() {
        let dir = temp("unreadable");
        let cfg = Config::app(dir.join("link.json"), dir.join("Downloads"), "Desk PC".into());
        let store = Arc::new(MemoryStore::default());
        store.fail_reads.store(true, Ordering::SeqCst);
        let shared: Arc<dyn SecretStore> = store.clone();
        let deps = Deps { keystore: Arc::new(Keystore::new(shared)), discovery: Arc::new(FakeDiscovery::default()), emit: Arc::new(Capture::default()) };
        let svc = Service::spawn(|f| { tokio::spawn(f); }, cfg, deps);
        svc.start();
        let s = svc.snapshot().await.unwrap();
        assert!(s.problem.is_none(), "a launch says nothing about the store while the machine is not visible");
        svc.set_devices_open(true);
        let s = svc.snapshot().await.unwrap();
        assert_eq!(s.problem.as_deref(), Some(PEERS_PROBLEM), "looking at Devices does say it");
    }

    /// The shelf is not Devices: with Visible off, opening it reads nothing from the credential store and says nothing about it.
    #[tokio::test]
    async fn a_shelf_open_with_visible_off_reads_nothing_and_shows_no_problem() {
        let dir = temp("shelf-unreadable");
        let cfg = Config::app(dir.join("link.json"), dir.join("Downloads"), "Desk PC".into());
        let store = Arc::new(MemoryStore::default());
        store.fail_reads.store(true, Ordering::SeqCst);
        let shared: Arc<dyn SecretStore> = store.clone();
        let deps = Deps { keystore: Arc::new(Keystore::new(shared)), discovery: Arc::new(FakeDiscovery::default()), emit: Arc::new(Capture::default()) };
        let svc = Service::spawn(|f| { tokio::spawn(f); }, cfg, deps);
        svc.start();
        svc.set_shelf_open(true);
        let s = svc.snapshot().await.unwrap();
        assert!(s.problem.is_none(), "a shelf open says nothing about the store while the machine is not visible");
        assert!(store.accounts().is_empty());
    }

    #[tokio::test]
    async fn turning_visible_on_makes_the_identity() {
        let n = node("Desk PC");
        let _ = n.svc.snapshot().await;
        assert!(n.store.accounts().is_empty());
        n.svc.set_visible(true);
        wait_snap(&n, "listening", |s| s.listening).await;
        let accounts = n.store.accounts();
        assert!(accounts.iter().any(|a| a == "link.device-id") && accounts.iter().any(|a| a == "link.static-key"), "{accounts:?}");
    }

    /// The machines of a pairing that ended after Visible was turned off are not the current ones: only the current run writes the shared pairing states.
    #[test]
    fn a_stale_pairing_end_leaves_the_shared_pairing_states_alone() {
        let dir = temp("core");
        let cfg = Config::app(dir.join("link.json"), dir.join("Downloads"), "Desk PC".into());
        let store: Arc<dyn SecretStore> = Arc::new(MemoryStore::default());
        let deps = Deps { keystore: Arc::new(Keystore::new(store)), discovery: Arc::new(FakeDiscovery::default()), emit: Arc::new(Capture::default()) };
        let (tx, _rx) = mpsc::unbounded_channel();
        let settings = settings::load(&cfg.settings_path, &cfg.host);
        let mut core = Core::new(cfg, deps, settings, tx);
        core.gate.stop(); // the generation is 1 now; a run made under 0 is stale
        let before = core.pairing.clone();
        let (i, r) = (Initiator::new(Ids { own_id: OwnId::Id("ab".repeat(16)), paired: None }), Responder::new(Ids { own_id: OwnId::Id("cd".repeat(16)), paired: None }));
        assert_ne!((i.clone(), r.clone()), before, "the control values differ from the shared ones");
        core.pair_ended(PairOutcome::Refused("handshake".into()), Some(i.clone()), Some(r.clone()), "ab", 0, false);
        assert_eq!(core.pairing, before, "a stale end changed the shared pairing states");
        core.pair_ended(PairOutcome::Refused("handshake".into()), Some(i.clone()), Some(r.clone()), "ab", 1, false);
        assert_eq!(core.pairing, (i, r), "the current run does write them");
    }

    /// A forget that failed leaves its problem on screen: the read that follows it must not clear it.
    #[tokio::test]
    async fn a_forget_that_failed_leaves_its_problem_visible() {
        let (a, b) = paired().await;
        a.store.fail_writes.store(true, Ordering::SeqCst);
        a.svc.forget(id_of(&b));
        wait_snap(&a, "the problem", |s| s.problem.as_deref() == Some(PEERS_PROBLEM)).await;
        let s = a.svc.snapshot().await.unwrap();
        assert_eq!(s.problem.as_deref(), Some(PEERS_PROBLEM));
        assert_eq!(s.rows.len(), 1, "the machine is still paired: the store would not take the change");
    }
}
