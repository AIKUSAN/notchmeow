// The pairing (docs/LINK-CONTRACT.md, "The pairing code"): the commitment, the six digits, the clocks, the gate on incoming pairings and the two machines (the responder's and the
// initiator's). A port of the matching functions of tests/fixtures/link/reference.py, replayed against pairing-cases.json. The machines take one event at a time and answer
// {state, send, notify, because}; they read no clock and draw no random number (the caller gives `now` and the nonces). Pure.
//
// Hex strings stay strings here, as in the reference: a value that is not exactly 64 (or 32) lower-case hex digits is a refusal named by the contract, so the machine checks them itself.

use std::collections::BTreeMap;

use sha2::{Digest, Sha256};

use super::bytes;

pub const COMMIT_LABEL: &[u8] = b"notchmeow-link pairing commit v1";
pub const CODE_LABEL: &[u8] = b"notchmeow-link pairing code v1";
pub const CODE_DIGITS: usize = 6;
/// At most one pairing attempt every 30 seconds.
pub const GAP_MS: i64 = 30_000;
/// The pairing window closes after 2 minutes.
pub const WINDOW_MS: i64 = 120_000;
/// An offer nobody answers is declined after 2 minutes.
pub const OFFER_TIMEOUT_MS: i64 = 120_000;

pub fn commit_of(nonce: &[u8; 32], static_pub: &[u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(COMMIT_LABEL);
    h.update(static_pub);
    h.update(nonce);
    h.finalize().into()
}

/// The six digits both screens show: SHA-256 over the label, the initiator's static key, the responder's static key, the initiator's nonce and the responder's nonce; the first 8 bytes
/// as a big-endian number; modulo 10^6; leading zeros kept. The handshake hash is deliberately not an input.
pub fn pairing_code(nonce_i: &[u8; 32], nonce_r: &[u8; 32], static_i: &[u8; 32], static_r: &[u8; 32]) -> String {
    let mut h = Sha256::new();
    h.update(CODE_LABEL);
    h.update(static_i);
    h.update(static_r);
    h.update(nonce_i);
    h.update(nonce_r);
    let d = h.finalize();
    let n = u64::from_be_bytes(d[..8].try_into().unwrap()) % 1_000_000;
    format!("{n:06}")
}

// ── The clocks (whole milliseconds on a monotonic clock; a negative value is "not a time") ──

fn whole(ms: i64) -> bool {
    ms >= 0
}

/// `last` is None for the first attempt. Allowed when 30 s have passed (exactly 30 s is allowed); a clock that went back, or a value that is not a time, refuses.
pub fn attempt_allowed(last: Option<i64>, now: i64) -> bool {
    if !whole(now) || last.is_some_and(|l| !whole(l)) {
        return false;
    }
    last.map_or(true, |l| now - l >= GAP_MS)
}

/// Open below 120 s after `start`.
pub fn window_open(start: i64, now: i64) -> bool {
    whole(start) && whole(now) && (0..WINDOW_MS).contains(&(now - start))
}

/// Expired at exactly 120 s. A clock that went back, or a bad value, counts as expired: declining is the safe side.
pub fn offer_expired(offered: i64, now: i64) -> bool {
    !(whole(offered) && whole(now) && (0..OFFER_TIMEOUT_MS).contains(&(now - offered)))
}

/// Who may start an incoming pairing: only while Settings → Devices is open, or within 2 minutes after the user clicked "Pair a machine" here (the owner's answer of 2026-10-15). At any other
/// time the hello is refused silently. Several windows may show Devices, so the opening is a count.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Gate {
    devices_open: u32,
    clicked_at: Option<i64>,
}

impl Gate {
    pub fn devices_appeared(&mut self) {
        self.devices_open += 1;
    }
    pub fn devices_disappeared(&mut self) {
        self.devices_open = self.devices_open.saturating_sub(1);
    }
    pub fn pair_clicked(&mut self, now: i64) {
        self.clicked_at = Some(now);
    }
    /// `now` is None when there is no clock: refused unless Devices is open.
    pub fn allows(&self, now: Option<i64>) -> bool {
        self.devices_open > 0 || matches!((self.clicked_at, now), (Some(c), Some(n)) if window_open(c, n))
    }
}

// ── The two machines ─────────────────────────────────────────────────────────

/// Why a pairing was refused. The connection is closed, nothing is sent, and the cause stays in the local log; `as_str` is the contract's word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    CommitLength,
    CommitReplayed,
    AttemptTooSoon,
    NoCommit,
    RevealLate,
    RevealLength,
    RevealMismatch,
    DeviceId,
    OwnId,
    IdKeyMismatch,
    Unexpected,
    StartLength,
    NonceRepeated,
    NonceLength,
    WindowClosed,
    SaidNo,
}

impl Refusal {
    pub fn as_str(self) -> &'static str {
        match self {
            Refusal::CommitLength => "commit-length",
            Refusal::CommitReplayed => "commit-replayed",
            Refusal::AttemptTooSoon => "attempt-too-soon",
            Refusal::NoCommit => "no-commit",
            Refusal::RevealLate => "reveal-late",
            Refusal::RevealLength => "reveal-length",
            Refusal::RevealMismatch => "reveal-mismatch",
            Refusal::DeviceId => "device-id",
            Refusal::OwnId => "own-id",
            Refusal::IdKeyMismatch => "id-key-mismatch",
            Refusal::Unexpected => "unexpected",
            Refusal::StartLength => "start-length",
            Refusal::NonceRepeated => "nonce-repeated",
            Refusal::NonceLength => "nonce-length",
            Refusal::WindowClosed => "window-closed",
            Refusal::SaidNo => "said-no",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notify {
    NonceSent,
    CommitSent,
    ShowCode,
    Store,
    Discard,
}

impl Notify {
    pub fn as_str(self) -> &'static str {
        match self {
            Notify::NonceSent => "nonce-sent",
            Notify::CommitSent => "commit-sent",
            Notify::ShowCode => "show-code",
            Notify::Store => "store",
            Notify::Discard => "discard",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Say {
    Nonce(String),
    Commit(String),
    Reveal(String),
    Pair(bool),
}

/// A machine's own device id. `Null` exists for the fixtures (present and not an id: every hello is then refused); an app passes `Absent` until it has an id, then `Id`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum OwnId {
    #[default]
    Absent,
    Null,
    Id(String),
}

/// The two inputs a machine keeps from one step to the next: its own device id and the devices it has paired (device id to the static key stored for it, both lower-case hex).
/// `paired` is None when it was not given (an empty map is a different state in the fixtures).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Ids {
    pub own_id: OwnId,
    pub paired: Option<BTreeMap<String, String>>,
}

fn id_hex(s: &str) -> bool {
    bytes::is_id_hex(s)
}

fn key_hex(s: &str) -> bool {
    bytes::is_key_hex(s)
}

/// False when the machine's own id, if it has one, is not 32 lower-case hex digits, or a paired id is not, or a paired key is not 64. Fail closed: a capital letter is never lower-cased.
fn ids_canonical(ids: &Ids) -> bool {
    let own = match &ids.own_id {
        OwnId::Absent => true,
        OwnId::Null => false,
        OwnId::Id(s) => id_hex(s),
    };
    own && ids.paired.iter().flatten().all(|(i, k)| id_hex(i) && key_hex(k))
}

/// Why a peer's hello is refused, given the machine's own id and its paired devices. The static key compared is the one the Noise handshake authenticated, never a value in the hello.
fn peer_refusal(ids: &Ids, peer_id: Option<&str>, peer_static: &str, length_reason: Refusal) -> Option<Refusal> {
    let Some(peer) = peer_id.filter(|p| id_hex(p)) else { return Some(length_reason) };
    if peer == "00".repeat(bytes::ID_LEN) {
        return Some(Refusal::DeviceId);
    }
    if !ids_canonical(ids) {
        return Some(Refusal::DeviceId);
    }
    if matches!(&ids.own_id, OwnId::Id(o) if o == peer) {
        return Some(Refusal::OwnId);
    }
    if ids.paired.as_ref().and_then(|p| p.get(peer)).is_some_and(|k| k != peer_static) {
        return Some(Refusal::IdKeyMismatch);
    }
    None
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Out<S> {
    pub state: S,
    pub send: Vec<Say>,
    pub notify: Option<Notify>,
    pub because: Option<Refusal>,
}

fn out<S>(state: S) -> Out<S> {
    Out { state, send: vec![], notify: None, because: None }
}

fn refuse<S>(state: S, because: Refusal) -> Out<S> {
    Out { because: Some(because), ..out(state) }
}

/// What the two users said, after the code is shown: `mine` is this user's click on "They match", `theirs` the other side's `pair-yes`. A "no" ends the pairing, so it is never kept here.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Answers {
    pub mine: bool,
    pub theirs: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Seen {
    pub commit: String,
    pub at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RPhase {
    Idle,
    Committed { commit: String, start: i64, nonce: String },
    Coded { start: i64, code: String, answers: Answers },
}

/// The responder: the machine that is asked to pair. `seen` is the recent commitments the app keeps across connections, `last` the time of the last attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Responder {
    pub phase: RPhase,
    pub seen: Vec<Seen>,
    pub last: Option<i64>,
    pub ids: Ids,
}

impl Responder {
    pub fn new(ids: Ids) -> Responder {
        Responder { phase: RPhase::Idle, seen: vec![], last: None, ids }
    }
    fn idle(&self) -> Responder {
        Responder { phase: RPhase::Idle, ..self.clone() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reveal {
    pub nonce: String,
    pub static_key: String,
    pub own: String,
    pub peer_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum REvent {
    /// The first message arrived: the commitment, and the app's fresh nonce.
    Commit { commit: String, nonce: String, now: i64 },
    /// The third message was opened: the initiator's nonce and static key, this machine's own static key, and the initiator's device id from its hello.
    Reveal { reveal: Reveal, now: i64 },
    User { yes: bool, now: i64 },
    Peer { yes: bool, now: i64 },
    /// Anything the machine does not know: nothing changes.
    Other,
}

/// What both machines do after the code is shown: a click, or the other side's answer. Anything but exactly "yes" is a no.
fn answer<S>(answers: Answers, start: i64, who_mine: bool, yes: bool, now: i64, idle: S, keep: impl FnOnce(Answers) -> S) -> Out<S> {
    if !window_open(start, now) {
        return Out { notify: Some(Notify::Discard), because: Some(Refusal::WindowClosed), ..out(idle) };
    }
    if !yes {
        return Out { send: if who_mine { vec![Say::Pair(false)] } else { vec![] }, notify: Some(Notify::Discard), because: Some(Refusal::SaidNo), ..out(idle) };
    }
    let new = if who_mine { Answers { mine: true, ..answers } } else { Answers { theirs: true, ..answers } };
    let send = if who_mine { vec![Say::Pair(true)] } else { vec![] };
    if new.mine && new.theirs {
        return Out { send, notify: Some(Notify::Store), ..out(idle) };
    }
    Out { send, ..out(keep(new)) }
}

pub fn responder_step(m: &Responder, ev: &REvent) -> Out<Responder> {
    let idle = m.idle();
    match ev {
        REvent::Commit { commit, nonce, now } => {
            if !matches!(m.phase, RPhase::Idle) {
                return refuse(idle, Refusal::Unexpected);
            }
            if !key_hex(commit) || !key_hex(nonce) {
                return refuse(idle, Refusal::CommitLength);
            }
            if m.seen.iter().any(|e| &e.commit == commit && window_open(e.at, *now)) {
                return refuse(idle, Refusal::CommitReplayed); // checked before the gap, so a replay is named as one
            }
            if !attempt_allowed(m.last, *now) {
                return refuse(idle, Refusal::AttemptTooSoon);
            }
            let mut seen: Vec<Seen> = m.seen.iter().filter(|e| window_open(e.at, *now)).cloned().collect();
            seen.push(Seen { commit: commit.clone(), at: *now });
            Out {
                send: vec![Say::Nonce(nonce.clone())],
                notify: Some(Notify::NonceSent),
                ..out(Responder { phase: RPhase::Committed { commit: commit.clone(), start: *now, nonce: nonce.clone() }, seen, last: Some(*now), ids: m.ids.clone() })
            }
        }
        REvent::Reveal { reveal: r, now } => {
            let (commit, start, nonce) = match &m.phase {
                RPhase::Idle => return refuse(idle, Refusal::NoCommit), // a reveal with no commitment before it
                RPhase::Committed { commit, start, nonce } => (commit, *start, nonce),
                RPhase::Coded { .. } => return refuse(idle, Refusal::Unexpected),
            };
            if !window_open(start, *now) {
                return refuse(idle, Refusal::RevealLate);
            }
            let (Some(rn), Some(rs), Some(own)) = (bytes::key32(&r.nonce), bytes::key32(&r.static_key), bytes::key32(&r.own)) else { return refuse(idle, Refusal::RevealLength) };
            if bytes::hex(&commit_of(&rn, &rs)) != *commit {
                return refuse(idle, Refusal::RevealMismatch); // a wrong nonce and a wrong key look the same, on purpose
            }
            if let Some(why) = peer_refusal(&m.ids, r.peer_id.as_deref(), &r.static_key, Refusal::RevealLength) {
                return refuse(idle, why);
            }
            let code = pairing_code(&rn, &bytes::key32(nonce).unwrap_or([0; 32]), &rs, &own);
            Out { notify: Some(Notify::ShowCode), ..out(Responder { phase: RPhase::Coded { start, code, answers: Answers::default() }, ..idle }) }
        }
        REvent::User { yes, now } | REvent::Peer { yes, now } => {
            let RPhase::Coded { start, code, answers } = &m.phase else { return out(m.clone()) }; // an answer before there is a code is ignored
            let mine = matches!(ev, REvent::User { .. });
            answer(*answers, *start, mine, *yes, *now, idle, |a| Responder { phase: RPhase::Coded { start: *start, code: code.clone(), answers: a }, ..m.clone() })
        }
        REvent::Other => out(m.clone()),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IPhase {
    Idle,
    Started { nonce: String, static_key: String, start: i64 },
    Coded { start: i64, code: String, answers: Answers },
}

/// The initiator: the machine whose user started the pairing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Initiator {
    pub phase: IPhase,
    pub last: Option<i64>,
    pub ids: Ids,
}

impl Initiator {
    pub fn new(ids: Ids) -> Initiator {
        Initiator { phase: IPhase::Idle, last: None, ids }
    }
    fn idle(&self) -> Initiator {
        Initiator { phase: IPhase::Idle, ..self.clone() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IEvent {
    /// The user chose Pair a machine: the app's fresh nonce and its static public key.
    Start { nonce: String, static_key: String, now: i64 },
    /// The second message was opened: the responder's nonce and static key, and the responder's device id from its hello.
    Nonce { nonce: String, peer_static: String, peer_id: Option<String>, now: i64 },
    User { yes: bool, now: i64 },
    Peer { yes: bool, now: i64 },
    Other,
}

pub fn initiator_step(m: &Initiator, ev: &IEvent) -> Out<Initiator> {
    let idle = m.idle();
    match ev {
        IEvent::Start { nonce, static_key, now } => {
            if !matches!(m.phase, IPhase::Idle) {
                return refuse(idle, Refusal::Unexpected);
            }
            let (Some(n), Some(s)) = (bytes::key32(nonce), bytes::key32(static_key)) else { return refuse(idle, Refusal::StartLength) };
            if !attempt_allowed(m.last, *now) {
                return refuse(idle, Refusal::AttemptTooSoon);
            }
            Out {
                send: vec![Say::Commit(bytes::hex(&commit_of(&n, &s)))],
                notify: Some(Notify::CommitSent),
                ..out(Initiator { phase: IPhase::Started { nonce: nonce.clone(), static_key: static_key.clone(), start: *now }, last: Some(*now), ids: m.ids.clone() })
            }
        }
        IEvent::Nonce { nonce, peer_static, peer_id, now } => {
            let (my_nonce, my_static, start) = match &m.phase {
                IPhase::Idle => return refuse(idle, Refusal::NoCommit), // the other side's nonce with no commitment of ours before it
                IPhase::Started { nonce, static_key, start } => (nonce, static_key, *start),
                IPhase::Coded { .. } => return refuse(idle, Refusal::NonceRepeated),
            };
            if !window_open(start, *now) {
                return refuse(idle, Refusal::RevealLate);
            }
            let (Some(rn), Some(rs)) = (bytes::key32(nonce), bytes::key32(peer_static)) else { return refuse(idle, Refusal::NonceLength) };
            if let Some(why) = peer_refusal(&m.ids, peer_id.as_deref(), peer_static, Refusal::NonceLength) {
                return refuse(idle, why);
            }
            let (Some(mn), Some(ms)) = (bytes::key32(my_nonce), bytes::key32(my_static)) else { return refuse(idle, Refusal::Unexpected) };
            let code = pairing_code(&mn, &rn, &ms, &rs);
            Out {
                send: vec![Say::Reveal(my_nonce.clone())],
                notify: Some(Notify::ShowCode),
                ..out(Initiator { phase: IPhase::Coded { start, code, answers: Answers::default() }, ..idle })
            }
        }
        IEvent::User { yes, now } | IEvent::Peer { yes, now } => {
            let IPhase::Coded { start, code, answers } = &m.phase else { return out(m.clone()) };
            let mine = matches!(ev, IEvent::User { .. });
            answer(*answers, *start, mine, *yes, *now, idle, |a| Initiator { phase: IPhase::Coded { start: *start, code: code.clone(), answers: a }, ..m.clone() })
        }
        IEvent::Other => out(m.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Map, Value};

    // ── JSON in and out, the fixtures' way ──

    fn s(v: &Value) -> String {
        v.as_str().unwrap().to_string()
    }

    fn ids_of(state: &Value) -> Ids {
        let own_id = match state.get("own_id") {
            None => OwnId::Absent,
            Some(Value::Null) => OwnId::Null,
            Some(v) => OwnId::Id(s(v)),
        };
        let paired = state.get("paired").map(|p| p.as_object().unwrap().iter().map(|(k, v)| (k.clone(), s(v))).collect());
        Ids { own_id, paired }
    }

    fn put_ids(o: &mut Map<String, Value>, ids: &Ids) {
        match &ids.own_id {
            OwnId::Absent => {}
            OwnId::Null => {
                o.insert("own_id".into(), Value::Null);
            }
            OwnId::Id(i) => {
                o.insert("own_id".into(), json!(i));
            }
        }
        if let Some(p) = &ids.paired {
            o.insert("paired".into(), Value::Object(p.iter().map(|(k, v)| (k.clone(), json!(v))).collect()));
        }
    }

    /// A field of an event that may be missing or not text: "" is not hex, and the machine refuses it by its length.
    fn t(v: &Value) -> String {
        v.as_str().unwrap_or("").to_string()
    }

    fn yes_of(v: &Value) -> bool {
        v == "yes"
    }

    fn answers_json(o: &mut Map<String, Value>, a: Answers) {
        o.insert("mine".into(), if a.mine { json!("yes") } else { Value::Null });
        o.insert("theirs".into(), if a.theirs { json!("yes") } else { Value::Null });
    }

    fn responder_of(v: &Value) -> Responder {
        let seen = v["seen"].as_array().unwrap().iter().map(|e| Seen { commit: s(&e["commit"]), at: e["at"].as_i64().unwrap() }).collect();
        let answers = Answers { mine: v["mine"] == "yes", theirs: v["theirs"] == "yes" };
        let phase = match v["s"].as_str().unwrap() {
            "idle" => RPhase::Idle,
            "committed" => RPhase::Committed { commit: s(&v["commit"]), start: v["start"].as_i64().unwrap(), nonce: s(&v["nonce"]) },
            "coded" => RPhase::Coded { start: v["start"].as_i64().unwrap(), code: s(&v["code"]), answers },
            other => panic!("state {other}"),
        };
        Responder { phase, seen, last: v["last"].as_i64(), ids: ids_of(v) }
    }

    fn responder_json(m: &Responder) -> Value {
        let mut o = Map::new();
        match &m.phase {
            RPhase::Idle => {
                o.insert("s".into(), json!("idle"));
            }
            RPhase::Committed { commit, start, nonce } => {
                o.insert("s".into(), json!("committed"));
                o.insert("commit".into(), json!(commit));
                o.insert("start".into(), json!(start));
                o.insert("nonce".into(), json!(nonce));
            }
            RPhase::Coded { start, code, answers } => {
                o.insert("s".into(), json!("coded"));
                o.insert("start".into(), json!(start));
                o.insert("code".into(), json!(code));
                answers_json(&mut o, *answers);
            }
        }
        o.insert("seen".into(), Value::Array(m.seen.iter().map(|e| json!({"commit": e.commit, "at": e.at})).collect()));
        o.insert("last".into(), json!(m.last));
        put_ids(&mut o, &m.ids);
        Value::Object(o)
    }

    fn initiator_of(v: &Value) -> Initiator {
        let answers = Answers { mine: v["mine"] == "yes", theirs: v["theirs"] == "yes" };
        let phase = match v["s"].as_str().unwrap() {
            "idle" => IPhase::Idle,
            "started" => IPhase::Started { nonce: s(&v["nonce"]), static_key: s(&v["static"]), start: v["start"].as_i64().unwrap() },
            "coded" => IPhase::Coded { start: v["start"].as_i64().unwrap(), code: s(&v["code"]), answers },
            other => panic!("state {other}"),
        };
        Initiator { phase, last: v["last"].as_i64(), ids: ids_of(v) }
    }

    fn initiator_json(m: &Initiator) -> Value {
        let mut o = Map::new();
        match &m.phase {
            IPhase::Idle => {
                o.insert("s".into(), json!("idle"));
            }
            IPhase::Started { nonce, static_key, start } => {
                o.insert("s".into(), json!("started"));
                o.insert("nonce".into(), json!(nonce));
                o.insert("static".into(), json!(static_key));
                o.insert("start".into(), json!(start));
            }
            IPhase::Coded { start, code, answers } => {
                o.insert("s".into(), json!("coded"));
                o.insert("start".into(), json!(start));
                o.insert("code".into(), json!(code));
                answers_json(&mut o, *answers);
            }
        }
        o.insert("last".into(), json!(m.last));
        put_ids(&mut o, &m.ids);
        Value::Object(o)
    }

    fn send_json(list: &[Say]) -> Value {
        Value::Array(
            list.iter()
                .map(|x| match x {
                    Say::Nonce(h) => json!({"nonce": h}),
                    Say::Commit(h) => json!({"commit": h}),
                    Say::Reveal(h) => json!({"reveal": h}),
                    Say::Pair(y) => json!({"pair": if *y { "yes" } else { "no" }}),
                })
                .collect(),
        )
    }

    fn out_json<S>(o: &Out<S>, state: Value) -> Value {
        json!({"state": state, "send": send_json(&o.send), "notify": o.notify.map(Notify::as_str), "because": o.because.map(Refusal::as_str)})
    }

    fn responder_event(e: &Value) -> REvent {
        let now = e["now"].as_i64().unwrap_or(0);
        if e.get("commit").is_some() {
            return REvent::Commit { commit: t(&e["commit"]), nonce: t(&e["nonce"]), now };
        }
        if let Some(r) = e.get("reveal") {
            let reveal = Reveal { nonce: t(&r["nonce"]), static_key: t(&r["static"]), own: t(&r["own"]), peer_id: r.get("peerId").and_then(Value::as_str).map(str::to_string) };
            return REvent::Reveal { reveal, now };
        }
        if let Some(u) = e.get("user") {
            return REvent::User { yes: yes_of(u), now };
        }
        if let Some(p) = e.get("peer") {
            return REvent::Peer { yes: yes_of(p), now };
        }
        REvent::Other
    }

    fn initiator_event(e: &Value) -> IEvent {
        let now = e["now"].as_i64().unwrap_or(0);
        if let Some(st) = e.get("start") {
            return IEvent::Start { nonce: t(&st["nonce"]), static_key: t(&st["static"]), now };
        }
        if e.get("nonce").is_some() {
            return IEvent::Nonce { nonce: t(&e["nonce"]), peer_static: t(&e["peerStatic"]), peer_id: e.get("peerId").and_then(Value::as_str).map(str::to_string), now };
        }
        if let Some(u) = e.get("user") {
            return IEvent::User { yes: yes_of(u), now };
        }
        if let Some(p) = e.get("peer") {
            return IEvent::Peer { yes: yes_of(p), now };
        }
        IEvent::Other
    }

    fn run_responder(state: &Value, ev: &Value) -> (Value, Value) {
        let o = responder_step(&responder_of(state), &responder_event(ev));
        let st = responder_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    fn run_initiator(state: &Value, ev: &Value) -> (Value, Value) {
        let o = initiator_step(&initiator_of(state), &initiator_event(ev));
        let st = initiator_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    // ── The tests ──

    #[test]
    fn the_numbers_are_the_fixtures() {
        let f = fixture("pairing-cases.json");
        assert_eq!(f["digits"], CODE_DIGITS);
        assert_eq!(f["commitLabel"].as_str().unwrap().as_bytes(), COMMIT_LABEL);
        assert_eq!(f["codeLabel"].as_str().unwrap().as_bytes(), CODE_LABEL);
        assert_eq!(f["gapMs"], GAP_MS);
        assert_eq!(f["windowMs"], WINDOW_MS);
        assert_eq!(f["offerTimeoutMs"], OFFER_TIMEOUT_MS);
    }

    #[test]
    fn commitments_and_codes() {
        let f = fixture("pairing-cases.json");
        for c in arr(&f, "commits") {
            let got = commit_of(&bytes::key32(c["nonce"].as_str().unwrap()).unwrap(), &bytes::key32(c["static"].as_str().unwrap()).unwrap());
            assert_eq!(bytes::hex(&got), c["commit"].as_str().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "codes") {
            let k = |n: &str| bytes::key32(c[n].as_str().unwrap()).unwrap();
            assert_eq!(pairing_code(&k("nonceI"), &k("nonceR"), &k("staticI"), &k("staticR")), c["code"].as_str().unwrap(), "{}", name(c));
        }
        // Invalid inputs never get this far: the machines check the length first.
        for c in arr(&f, "invalid") {
            assert!(c["value"].as_str().map_or(true, |v| bytes::key32(v).is_none()), "{}", name(c));
        }
    }

    #[test]
    fn the_session_of_the_xx_vector_has_this_commitment_and_this_code() {
        let f = fixture("pairing-cases.json");
        let t = &f["session"];
        let k = |n: &str| bytes::key32(t[n].as_str().unwrap()).unwrap();
        assert_eq!(bytes::hex(&commit_of(&k("nonceI"), &k("staticI"))), t["commit"].as_str().unwrap());
        assert_eq!(pairing_code(&k("nonceI"), &k("nonceR"), &k("staticI"), &k("staticR")), t["code"].as_str().unwrap());
    }

    fn ms(v: &Value) -> i64 {
        v.as_i64().unwrap_or(-1) // text, true, null: not a time
    }

    #[test]
    fn the_three_clocks() {
        let f = fixture("pairing-cases.json");
        for c in arr(&f, "gapCases") {
            let last = if c["last"].is_null() { None } else { Some(ms(&c["last"])) };
            assert_eq!(attempt_allowed(last, ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "windowCases") {
            assert_eq!(window_open(ms(&c["start"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
        for c in arr(&f, "offerCases") {
            assert_eq!(offer_expired(ms(&c["offered"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn the_responder_row_by_row() {
        let f = fixture("pairing-cases.json");
        let rows = arr(&f, "responder");
        assert!(rows.len() >= 47);
        for c in rows {
            assert_eq!(run_responder(&c["state"], &c["event"]).0, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn the_initiator_row_by_row() {
        let f = fixture("pairing-cases.json");
        let rows = arr(&f, "initiator");
        assert!(rows.len() >= 27);
        for c in rows {
            assert_eq!(run_initiator(&c["state"], &c["event"]).0, c["out"], "{}", name(c));
        }
    }

    #[test]
    fn whole_pairings_event_by_event() {
        let f = fixture("pairing-cases.json");
        for t in arr(&f, "machineTrips") {
            let mut state = t["from"].clone();
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let (got, next) = if t["side"] == "responder" { run_responder(&state, e) } else { run_initiator(&state, e) };
                assert_eq!(got, outs[i], "{} step {i}", name(t));
                state = next;
            }
        }
    }

    #[test]
    fn the_gate_opens_for_devices_and_for_two_minutes_after_a_click() {
        let mut g = Gate::default();
        assert!(!g.allows(Some(0)), "nothing open, no click");
        g.pair_clicked(1_000);
        assert!(g.allows(Some(1_000)), "open at the click");
        assert!(g.allows(Some(120_999)), "open 1 ms before 2 minutes");
        assert!(!g.allows(Some(121_000)), "closed at exactly 120 s");
        assert!(!g.allows(Some(500)), "a clock that went back");
        assert!(!g.allows(None), "no clock");
        g.devices_appeared();
        assert!(g.allows(None), "Devices open: any time");
        g.devices_appeared();
        g.devices_disappeared();
        assert!(g.allows(Some(900_000)), "two windows showed Devices, one closed");
        g.devices_disappeared();
        g.devices_disappeared();
        assert!(!g.allows(Some(900_000)), "closing more than was opened does not go below zero");
    }
}
