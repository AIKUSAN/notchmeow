// What each side of a transfer does with each frame (docs/LINK-CONTRACT.md, "What each side does with each frame"), and the three rules the app keeps around one connection: the machine's one
// transfer place, one machine-made decline per connection, and the first-frame clock. A port of `receiver_step`, `sender_step`, `place_step`, `receiver_connection_step` and
// `first_frame_expired` of tests/fixtures/link/reference.py, replayed against flow-cases.json. Pure: a state, one event, and the answer; no socket, no clock, no disk.
//
// Only a click (`User(Accept)`) starts a transfer. One transfer at a time on a connection; the app asks the machine's one transfer place (`Place`) before it lets an offer through.

use super::bytes::ID_LEN;
use super::frames::{Frame, DECLINE_BAD_OFFER, DECLINE_BUSY, DECLINE_TIMEOUT, DECLINE_TOO_LARGE, DECLINE_USER, SIZE_MAX};
use super::name::sanitize_name;

type Id = [u8; ID_LEN];

/// A transfer connection whose handshake is done must have an offer in hand within this long.
pub const FIRST_FRAME_MS: i64 = 10_000;
/// The machine-made declines one connection may send; the next one closes it.
pub const DECLINES_PER_CONNECTION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notify {
    Offer,
    Expired,
    Withdrawn,
    Cancelled,
    Complete,
    Declined,
}

impl Notify {
    pub fn as_str(self) -> &'static str {
        match self {
            Notify::Offer => "offer",
            Notify::Expired => "expired",
            Notify::Withdrawn => "withdrawn",
            Notify::Cancelled => "cancelled",
            Notify::Complete => "complete",
            Notify::Declined => "declined",
        }
    }
}

/// Why a connection must close. After an abort the state is idle and nothing is saved as complete. `Declines` and `Idle` come from the connection rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Abort {
    Unexpected,
    Id,
    Order,
    Overflow,
    Short,
    Declines,
    Idle,
}

impl Abort {
    pub fn as_str(self) -> &'static str {
        match self {
            Abort::Unexpected => "unexpected",
            Abort::Id => "id",
            Abort::Order => "order",
            Abort::Overflow => "overflow",
            Abort::Short => "short",
            Abort::Declines => "declines",
            Abort::Idle => "idle",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Out<S> {
    pub state: S,
    pub send: Vec<Frame>,
    pub notify: Option<Notify>,
    pub abort: Option<Abort>,
}

fn out<S>(state: S, send: Vec<Frame>, notify: Option<Notify>, abort: Option<Abort>) -> Out<S> {
    Out { state, send, notify, abort }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum User {
    Accept,
    Decline,
    Cancel,
}

// ── The receiver ─────────────────────────────────────────────────────────────

/// `name` is the sanitized name, the one that is shown and saved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RState {
    Idle,
    Offered { id: Id, size: u64, name: String },
    Receiving { id: Id, size: u64, got: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Frame(Frame),
    User(User),
    Timeout,
}

fn decline(id: Id, reason: u8) -> Frame {
    Frame::Decline { id, reason }
}

pub fn receiver_step(state: &RState, ev: &Event) -> Out<RState> {
    use RState::*;
    match ev {
        Event::User(u) => match (state, u) {
            (Offered { id, size, .. }, User::Accept) => out(Receiving { id: *id, size: *size, got: 0 }, vec![Frame::Accept { id: *id }], None, None),
            (Offered { id, .. }, User::Decline) => out(Idle, vec![decline(*id, DECLINE_USER)], None, None),
            (Receiving { id, .. }, User::Cancel | User::Decline) => out(Idle, vec![Frame::Cancel { id: *id }], Some(Notify::Cancelled), None),
            _ => out(state.clone(), vec![], None, None),
        },
        Event::Timeout => match state {
            Offered { id, .. } => out(Idle, vec![decline(*id, DECLINE_TIMEOUT)], Some(Notify::Expired), None),
            _ => out(state.clone(), vec![], None, None),
        },
        Event::Frame(f) => {
            if f.is_pairing_answer() {
                return out(Idle, vec![], None, Some(Abort::Unexpected)); // a pairing answer has no place in a transfer
            }
            match f {
                Frame::Offer { id, size, name, .. } => {
                    if !matches!(state, Idle) {
                        return out(state.clone(), vec![decline(*id, DECLINE_BUSY)], None, None);
                    }
                    if *size > SIZE_MAX {
                        return out(Idle, vec![decline(*id, DECLINE_TOO_LARGE)], None, None);
                    }
                    match sanitize_name(name) {
                        Ok(saved) => out(Offered { id: *id, size: *size, name: saved }, vec![], Some(Notify::Offer), None),
                        Err(_) => out(Idle, vec![decline(*id, DECLINE_BAD_OFFER)], None, None),
                    }
                }
                Frame::Cancel { id } => match state {
                    Offered { id: mine, .. } if mine == id => out(Idle, vec![], Some(Notify::Withdrawn), None),
                    Receiving { id: mine, .. } if mine == id => out(Idle, vec![], Some(Notify::Cancelled), None),
                    _ => out(state.clone(), vec![], None, None), // a cancel for a transfer we do not know is harmless
                },
                Frame::Chunk { id, offset, data } => match state {
                    Receiving { id: mine, size, got } => {
                        if id != mine {
                            return out(Idle, vec![], None, Some(Abort::Id));
                        }
                        if offset != got {
                            return out(Idle, vec![], None, Some(Abort::Order)); // a replayed chunk or a skipped one
                        }
                        if got + data.len() as u64 > *size {
                            return out(Idle, vec![], None, Some(Abort::Overflow));
                        }
                        out(Receiving { id: *mine, size: *size, got: got + data.len() as u64 }, vec![], None, None)
                    }
                    _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
                },
                Frame::Done { id } => match state {
                    Receiving { id: mine, size, got } => {
                        if id != mine {
                            return out(Idle, vec![], None, Some(Abort::Id));
                        }
                        if got != size {
                            return out(Idle, vec![], None, Some(Abort::Short));
                        }
                        out(Idle, vec![], Some(Notify::Complete), None)
                    }
                    _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
                },
                _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
            }
        }
    }
}

// ── The sender ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SState {
    Idle,
    Offered { id: Id },
    Sending { id: Id },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SEvent {
    Frame(Frame),
    UserCancel,
}

pub fn sender_step(state: &SState, ev: &SEvent) -> Out<SState> {
    use SState::*;
    let id = match state {
        Idle => None,
        Offered { id } | Sending { id } => Some(*id),
    };
    match ev {
        SEvent::UserCancel => match id {
            Some(id) => out(Idle, vec![Frame::Cancel { id }], Some(Notify::Cancelled), None),
            None => out(state.clone(), vec![], None, None),
        },
        SEvent::Frame(f) => {
            if id.is_none() && matches!(f, Frame::Cancel { .. }) {
                return out(state.clone(), vec![], None, None); // a cancel with no transfer running is ignored
            }
            let Some(mine) = id else { return out(Idle, vec![], None, Some(Abort::Unexpected)) };
            if matches!(f, Frame::Offer { .. } | Frame::Chunk { .. } | Frame::Done { .. }) || f.is_pairing_answer() {
                return out(Idle, vec![], None, Some(Abort::Unexpected));
            }
            if f.id() != Some(mine) {
                return out(Idle, vec![], None, Some(Abort::Id));
            }
            match (state, f) {
                (Offered { .. }, Frame::Accept { .. }) => out(Sending { id: mine }, vec![], None, None),
                (Offered { .. }, Frame::Decline { .. }) => out(Idle, vec![], Some(Notify::Declined), None),
                (_, Frame::Cancel { .. }) => out(Idle, vec![], Some(Notify::Cancelled), None),
                _ => out(Idle, vec![], None, Some(Abort::Unexpected)),
            }
        }
    }
}

// ── The rules around one connection ──────────────────────────────────────────

/// The first-frame clock: expired at exactly 10 s after the handshake. A clock that went back, or a value that is not a time (negative), counts as expired.
pub fn first_frame_expired(handshake_ms: i64, now_ms: i64) -> bool {
    !(handshake_ms >= 0 && now_ms >= 0 && (0..FIRST_FRAME_MS).contains(&(now_ms - handshake_ms)))
}

/// The machine's one transfer place, for every peer. `holder` is the id that holds it; `card` is true while a card with buttons is on the island.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Place {
    pub holder: Option<String>,
    pub card: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlaceEvent {
    /// An offer asks for the place: granted only when nobody holds it and no card is up, and then the claimant holds it.
    Claim(String),
    /// The holder gives it back; another id changes nothing.
    Release(String),
    /// A card with buttons goes up or comes down.
    Card(bool),
}

/// (the new place, Some(granted) for a claim).
pub fn place_step(place: &Place, ev: &PlaceEvent) -> (Place, Option<bool>) {
    match ev {
        PlaceEvent::Claim(id) => {
            if place.holder.is_none() && !place.card {
                (Place { holder: Some(id.clone()), card: place.card }, Some(true))
            } else {
                (place.clone(), Some(false))
            }
        }
        PlaceEvent::Release(id) => (Place { holder: if place.holder.as_ref() == Some(id) { None } else { place.holder.clone() }, card: place.card }, None),
        PlaceEvent::Card(on) => (Place { holder: place.holder.clone(), card: *on }, None),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conn {
    pub state: RState,
    /// The machine-made declines this connection has sent.
    pub declines: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnEvent {
    /// A receiver event. An offer may carry `granted`, the place's answer to its claim (true when absent).
    Receiver { event: Event, granted: Option<bool> },
    /// The first-frame clock has run out.
    Silent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnOut {
    pub conn: Conn,
    pub send: Vec<Frame>,
    pub notify: Option<Notify>,
    pub abort: Option<Abort>,
}

fn machine_decline(f: &Frame) -> bool {
    matches!(f, Frame::Decline { reason, .. } if matches!(*reason, DECLINE_BUSY | DECLINE_TOO_LARGE | DECLINE_BAD_OFFER))
}

/// One connection of the receiver as the app runs it: `receiver_step` plus the rules above. An offer that comes while the connection is idle asks the place: a refused one is declined as
/// busy (2) and the state does not change. A machine-made decline sent for an offer counts; the second one is not sent, the connection is closed (`Declines`). The user's no and a timeout do
/// not count. A silent clock closes an idle connection (`Idle`); in any other state its report is stale and does nothing.
pub fn connection_step(conn: &Conn, ev: &ConnEvent) -> ConnOut {
    let keep = |conn: &Conn, send, notify, abort| ConnOut { conn: conn.clone(), send, notify, abort };
    match ev {
        ConnEvent::Silent => {
            if conn.state == RState::Idle {
                return keep(&Conn { state: RState::Idle, declines: conn.declines }, vec![], None, Some(Abort::Idle));
            }
            keep(conn, vec![], None, None)
        }
        ConnEvent::Receiver { event, granted } => {
            let offer = matches!(event, Event::Frame(Frame::Offer { .. }));
            let res = match event {
                Event::Frame(Frame::Offer { id, .. }) if conn.state == RState::Idle && !granted.unwrap_or(true) => out(conn.state.clone(), vec![decline(*id, DECLINE_BUSY)], None, None),
                _ => receiver_step(&conn.state, event),
            };
            let mut declines = conn.declines;
            if offer && res.send.iter().any(machine_decline) {
                if declines >= DECLINES_PER_CONNECTION {
                    return ConnOut { conn: Conn { state: RState::Idle, declines }, send: vec![], notify: None, abort: Some(Abort::Declines) };
                }
                declines += 1;
            }
            ConnOut { conn: Conn { state: res.state, declines }, send: res.send, notify: res.notify, abort: res.abort }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::bytes;
    use crate::link::frames::tests::{frame_of, json_of};
    use crate::link::testutil::{arr, fixture, name};
    use serde_json::{json, Value};

    fn id_of(v: &Value) -> Id {
        bytes::id16(v.as_str().unwrap()).unwrap()
    }

    fn rstate_of(v: &Value) -> RState {
        match v["s"].as_str().unwrap() {
            "idle" => RState::Idle,
            "offered" => RState::Offered { id: id_of(&v["id"]), size: v["size"].as_u64().unwrap(), name: v["name"].as_str().unwrap().to_string() },
            "receiving" => RState::Receiving { id: id_of(&v["id"]), size: v["size"].as_u64().unwrap(), got: v["got"].as_u64().unwrap() },
            other => panic!("state {other}"),
        }
    }

    fn rstate_json(s: &RState) -> Value {
        match s {
            RState::Idle => json!({"s": "idle"}),
            RState::Offered { id, size, name } => json!({"s": "offered", "id": bytes::hex(id), "size": size, "name": name}),
            RState::Receiving { id, size, got } => json!({"s": "receiving", "id": bytes::hex(id), "size": size, "got": got}),
        }
    }

    fn sstate_of(v: &Value) -> SState {
        match v["s"].as_str().unwrap() {
            "idle" => SState::Idle,
            "offered" => SState::Offered { id: id_of(&v["id"]) },
            "sending" => SState::Sending { id: id_of(&v["id"]) },
            other => panic!("state {other}"),
        }
    }

    fn sstate_json(s: &SState) -> Value {
        match s {
            SState::Idle => json!({"s": "idle"}),
            SState::Offered { id } => json!({"s": "offered", "id": bytes::hex(id)}),
            SState::Sending { id } => json!({"s": "sending", "id": bytes::hex(id)}),
        }
    }

    fn event_of(e: &Value) -> Event {
        if let Some(f) = e.get("frame") {
            return Event::Frame(frame_of(f));
        }
        if let Some(u) = e.get("user") {
            return Event::User(match u.as_str().unwrap() {
                "accept" => User::Accept,
                "decline" => User::Decline,
                "cancel" => User::Cancel,
                other => panic!("user {other}"),
            });
        }
        assert!(e.get("timeout").is_some(), "event {e}");
        Event::Timeout
    }

    fn out_json<S>(o: &Out<S>, state: Value) -> Value {
        json!({"state": state, "send": o.send.iter().map(json_of).collect::<Vec<_>>(), "notify": o.notify.map(Notify::as_str), "abort": o.abort.map(Abort::as_str)})
    }

    fn run_receiver(state: &Value, ev: &Value) -> (Value, Value) {
        let o = receiver_step(&rstate_of(state), &event_of(ev));
        let st = rstate_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    fn run_sender(state: &Value, ev: &Value) -> (Value, Value) {
        let event = match (ev.get("frame"), ev.get("user")) {
            (Some(f), _) => SEvent::Frame(frame_of(f)),
            (_, Some(u)) => {
                assert_eq!(u, "cancel");
                SEvent::UserCancel
            }
            _ => panic!("event {ev}"),
        };
        let o = sender_step(&sstate_of(state), &event);
        let st = sstate_json(&o.state);
        (out_json(&o, st.clone()), st)
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let f = fixture("flow-cases.json");
        assert_eq!(f["chunkSize"], crate::link::frames::CHUNK_SIZE);
        assert_eq!(f["sizeMax"], SIZE_MAX);
        assert_eq!(f["firstFrameMs"], FIRST_FRAME_MS);
        assert_eq!(f["aborts"], json!(["unexpected", "id", "order", "overflow", "short"]));
    }

    #[test]
    fn the_receiver_and_the_sender_row_by_row() {
        let f = fixture("flow-cases.json");
        let (r, s) = (arr(&f, "receiver"), arr(&f, "sender"));
        assert!(r.len() >= 50 && s.len() >= 16);
        for c in r {
            assert_eq!(run_receiver(&c["state"], &c["event"]).0, c["out"], "receiver: {}", name(c));
        }
        for c in s {
            assert_eq!(run_sender(&c["state"], &c["event"]).0, c["out"], "sender: {}", name(c));
        }
    }

    #[test]
    fn whole_transfers_step_by_step() {
        let f = fixture("flow-cases.json");
        for t in arr(&f, "trips") {
            let mut state = t["from"].clone();
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let (got, next) = if t["side"] == "receiver" { run_receiver(&state, e) } else { run_sender(&state, e) };
                assert_eq!(got, outs[i], "{} step {i}", name(t));
                state = next;
            }
        }
    }

    #[test]
    fn the_machines_one_transfer_place() {
        let f = fixture("flow-cases.json");
        for t in arr(&f, "places") {
            let from = &t["from"];
            let mut place = Place { holder: from["holder"].as_str().map(str::to_string), card: from["card"].as_bool().unwrap() };
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let ev = if let Some(c) = e.get("claim") {
                    PlaceEvent::Claim(c.as_str().unwrap().to_string())
                } else if let Some(r) = e.get("release") {
                    PlaceEvent::Release(r.as_str().unwrap().to_string())
                } else {
                    PlaceEvent::Card(e["card"].as_bool().unwrap())
                };
                let (next, granted) = place_step(&place, &ev);
                place = next;
                let got = json!({"place": {"holder": place.holder, "card": place.card}, "granted": granted});
                assert_eq!(got, outs[i], "{} step {i}", name(t));
            }
        }
    }

    #[test]
    fn one_decline_per_connection_and_the_first_frame_clock() {
        let f = fixture("flow-cases.json");
        let rows = arr(&f, "connections");
        assert!(rows.len() >= 13);
        for t in rows {
            let from = &t["from"];
            let mut conn = Conn { state: rstate_of(&from["state"]), declines: from["declines"].as_u64().unwrap() as u32 };
            let outs = t["out"].as_array().unwrap();
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let ev = if e.get("silent").is_some() { ConnEvent::Silent } else { ConnEvent::Receiver { event: event_of(e), granted: e.get("granted").and_then(Value::as_bool) } };
                let o = connection_step(&conn, &ev);
                conn = o.conn.clone();
                let got = json!({"state": rstate_json(&conn.state), "declines": conn.declines, "send": o.send.iter().map(json_of).collect::<Vec<_>>(), "notify": o.notify.map(Notify::as_str), "abort": o.abort.map(Abort::as_str)});
                assert_eq!(got, outs[i], "{} step {i}", name(t));
            }
        }
        for c in arr(&f, "firstFrame") {
            let ms = |v: &Value| v.as_i64().unwrap_or(-1);
            assert_eq!(first_frame_expired(ms(&c["handshake"]), ms(&c["now"])), c["out"].as_bool().unwrap(), "{}", name(c));
        }
    }

    #[test]
    fn no_script_breaks_an_invariant() {
        // 3000 random scripts of events at one receiver: nothing panics, the count never passes the size, an abort lands in idle, only a click starts a transfer.
        let mut seed: u64 = 20261015;
        let mut next = |n: usize| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) as usize) % n
        };
        let ids = [[1u8; 16], [2u8; 16]];
        let names = ["a.txt", "../x", "CON", "a\0"];
        let sizes = [0u64, 5, 10, 1 << 32, (1 << 32) + 1];
        let offsets = [0u64, 2, 4, 6, 8, 10];
        for _ in 0..3000 {
            let mut state = RState::Idle;
            for _ in 0..1 + next(29) {
                let id = ids[next(2)];
                let ev = match next(6) {
                    0 => Event::Frame(Frame::Offer { id, size: sizes[next(5)], name: names[next(4)].to_string(), kind: String::new() }),
                    1 => Event::Frame(Frame::Chunk { id, offset: offsets[next(6)], data: vec![0xAB; 1 + next(4)] }),
                    2 => Event::Frame([Frame::Done { id }, Frame::Cancel { id }, Frame::Accept { id }][next(3)].clone()),
                    3 => Event::Frame(Frame::Decline { id, reason: 0 }),
                    4 => Event::User([User::Accept, User::Decline, User::Cancel][next(3)]),
                    _ => Event::Timeout,
                };
                let before = state.clone();
                let res = receiver_step(&state, &ev);
                state = res.state.clone();
                let started_by_click = !(matches!(state, RState::Receiving { .. }) && !matches!(before, RState::Receiving { .. })) || ev == Event::User(User::Accept);
                let overshoot = matches!(&state, RState::Receiving { size, got, .. } if got > size);
                assert!(!(res.abort.is_some() && state != RState::Idle) && !overshoot && started_by_click, "{before:?} {ev:?} -> {res:?}");
            }
        }
    }
}
