// The rules around the service, as plain values (sub-project G2): who holds the island's one link card and when a click may act on it, which conversation a late event belongs to, the
// machine's one transfer place, how many connections may be open, and how often the paired machines are read again. The Mac's twins are `LinkCardRules`, `LinkRunGate`, `LinkBusy`,
// `LinkConnectionCaps`, `LinkReadLimit` and `LinkClock` (NotchBuddy/Sources/App/LinkCardRules.swift); the cases below are the Mac's own test cases, ported. No clock is read in the rules:
// `now` is whole monotonic milliseconds, given by the caller (`now_ms`).

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

/// A click on a card that has only just changed kind is ignored for this long: a click aimed at the card that was there must not land on the button of the one that replaced it.
pub const SETTLE_MS: i64 = 700;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Pair,
    Offer,
    Receiving,
    Result,
}

impl Kind {
    /// A card with buttons the user is about to press (a result is only read, and may give way).
    pub fn interactive(self) -> bool {
        self != Kind::Result
    }
}

/// What the user was shown: the kind of card and a key for what it is about (the pairing code with the other machine's name, the offer key, the words of a result). The "answered" flag and
/// the progress are not part of it, so the user's own answer or a progress tick is not "another card".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shown {
    pub kind: Kind,
    pub key: String,
}

/// What identifies one offer: the machine and the id it chose. A transfer id alone is the other machine's own number, so two machines may use the same one.
pub fn offer_key(peer_id: &str, transfer_id: &str) -> String {
    format!("{peer_id}|{transfer_id}")
}

/// The service has a single card slot for pairing codes, offers, progress and results. What is on it is something the user is about to click: a pairing code or an offer from another machine
/// must never replace it (a click meant for "Accept" would land on another machine's "They match"), and a flow that ends must not wipe the card of another one.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CardRules {
    owner: Option<String>,
    shown: Option<Shown>,
    changed_at: i64,
}

impl CardRules {
    pub fn owner(&self) -> Option<&str> {
        self.owner.as_deref()
    }
    pub fn shown(&self) -> Option<&Shown> {
        self.shown.as_ref()
    }
    /// When the card last changed kind (or owner).
    pub fn changed_at(&self) -> i64 {
        self.changed_at
    }
    pub fn interactive(&self) -> bool {
        self.shown.as_ref().is_some_and(|s| s.kind.interactive())
    }

    /// A flow asks to put `card` on the island. False when another flow's card with buttons is up: nothing changes then, and the flow must not show anything.
    pub fn show(&mut self, card: Shown, owner: &str, now: i64) -> bool {
        if self.interactive() && self.owner.as_deref() != Some(owner) {
            return false;
        }
        if self.shown.as_ref().map(|s| s.kind) != Some(card.kind) || self.owner.as_deref() != Some(owner) {
            self.changed_at = now;
        }
        self.owner = Some(owner.to_string());
        self.shown = Some(card);
        true
    }

    /// A flow is over and has no card to leave: clears the card only if it is this flow's. False (and nothing changes) when the card belongs to another one.
    pub fn end(&mut self, owner: &str) -> bool {
        if self.owner.as_deref() != Some(owner) {
            return false;
        }
        self.owner = None;
        self.shown = None;
        true
    }

    /// May a click act now? `card` is the card the user saw when they clicked (None: the current one). False for a card that is no longer the one shown, and while the card is still settling.
    pub fn accepts(&self, card: Option<&Shown>, now: i64) -> bool {
        let Some(current) = &self.shown else { return false };
        if card.is_some_and(|c| c != current) {
            return false;
        }
        now - self.changed_at >= SETTLE_MS
    }
}

/// Which conversation a late event belongs to. Every hook a conversation gives the service reaches it through a task that may run after the conversation was cancelled, so the hook carries the
/// ticket its conversation was made under and the service acts only if that ticket is still the current one. A stop (Visible turned off) ends all of them at once, and a run that ended or was
/// replaced is stale as soon as another begins.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ticket {
    pub generation: u64,
    pub serial: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RunGate {
    generation: u64,
    serial: u64,
    pair: Option<Ticket>,
    receive: Option<Ticket>,
}

impl RunGate {
    /// Counts the stops. Whatever awaits remembers the number it started under.
    pub fn generation(&self) -> u64 {
        self.generation
    }
    pub fn stop(&mut self) {
        self.generation += 1;
        self.pair = None;
        self.receive = None;
    }
    pub fn begin_pair(&mut self) -> Ticket {
        let t = self.next();
        self.pair = Some(t);
        t
    }
    pub fn begin_receive(&mut self) -> Ticket {
        let t = self.next();
        self.receive = Some(t);
        t
    }
    fn next(&mut self) -> Ticket {
        self.serial += 1;
        Ticket { generation: self.generation, serial: self.serial }
    }
    pub fn end_pair(&mut self) {
        self.pair = None;
    }
    pub fn end_receive(&mut self) {
        self.receive = None;
    }
    pub fn is_pair(&self, t: Ticket) -> bool {
        self.pair == Some(t) && t.generation == self.generation
    }
    pub fn is_receive(&self, t: Ticket) -> bool {
        self.receive == Some(t) && t.generation == self.generation
    }
}

/// Who may take the island's card, decided where the transfer's own task can ask without leaving it (so the answer is exact when the offer arrives, not when the service gets to it). It is
/// the contract's `place_step` with a lock: one transfer for the whole machine.
#[derive(Debug, Default)]
pub struct Busy {
    inner: Mutex<BusyInner>,
}

#[derive(Debug, Default)]
struct BusyInner {
    peers: HashSet<String>,
    card_locked: bool,
}

impl Busy {
    /// False when a transfer is already claimed (by any machine: the island has one card), or a card with buttons is on the island (the offer is then declined as busy, and no card is shown).
    pub fn claim(&self, id: &str) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.card_locked || !g.peers.is_empty() {
            return false;
        }
        g.peers.insert(id.to_string())
    }
    pub fn release(&self, id: &str) {
        self.inner.lock().unwrap().peers.remove(id);
    }
    /// This peer's offer holds the machine's one transfer place: an Accept click for an offer whose run has ended is not for it.
    pub fn holds(&self, id: &str) -> bool {
        self.inner.lock().unwrap().peers.contains(id)
    }
    pub fn set_card_locked(&self, on: bool) {
        self.inner.lock().unwrap().card_locked = on;
    }
    /// A pairing code is about to take the card. False when an offer has been claimed and has not got its card yet (the pairing is ended instead; nothing is shown for it). Otherwise the card
    /// is locked at once, so an offer that arrives next is declined as busy at its claim, not after it passed.
    pub fn reserve_card(&self) -> bool {
        let mut g = self.inner.lock().unwrap();
        if !g.peers.is_empty() {
            return false;
        }
        g.card_locked = true;
        true
    }
}

/// How many connections may be established at once (their handshake done): 8 in all and 2 for one machine, so a machine that holds connections open and says nothing cannot take every
/// descriptor or crowd the other machines out. Connections that have not finished their handshake are bounded by the listener's own pending cap and its 10 seconds.
#[derive(Debug, Default)]
pub struct ConnectionCaps {
    owners: Mutex<HashMap<u64, String>>,
}

impl ConnectionCaps {
    pub const TOTAL: usize = 8;
    pub const PER_PEER: usize = 2;

    /// True when the connection `id` of `peer` may go on (and is counted from now until `release`).
    pub fn admit(&self, id: u64, peer: &str) -> bool {
        let mut g = self.owners.lock().unwrap();
        if g.contains_key(&id) {
            return true;
        }
        if g.len() >= Self::TOTAL || g.values().filter(|p| p.as_str() == peer).count() >= Self::PER_PEER {
            return false;
        }
        g.insert(id, peer.to_string());
        true
    }
    pub fn release(&self, id: u64) {
        self.owners.lock().unwrap().remove(&id);
    }
    pub fn count(&self) -> usize {
        self.owners.lock().unwrap().len()
    }
}

/// How often the paired machines are read from the credential store on a miss (an id this machine does not know) or by choice: once in 5 s, so a peer that sends ids that are not paired cannot
/// make the machine read the store in a loop, and a read that failed for a moment is tried again soon.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReadLimit {
    last: Option<i64>,
}

impl ReadLimit {
    pub const GAP_MS: i64 = 5_000;
    pub fn due(&self, now: i64) -> bool {
        self.last.map_or(true, |l| now - l >= Self::GAP_MS)
    }
    /// A read happened (whoever asked for it).
    pub fn read(&mut self, now: i64) {
        self.last = Some(now);
    }
}

/// The link's whole-millisecond clock: monotonic, and it keeps counting while the machine sleeps, as a window that was measured by it and one that was slept for should end together.
/// Only differences mean anything. Linux: `CLOCK_BOOTTIME`. Windows: `GetTickCount64`, which includes sleep (the unbiased interrupt time does not).
pub fn now_ms() -> i64 {
    #[cfg(target_os = "linux")]
    {
        let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
        // SAFETY: `ts` is a valid timespec and CLOCK_BOOTTIME exists on every Linux this app supports.
        unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut ts) };
        ts.tv_sec as i64 * 1000 + ts.tv_nsec as i64 / 1_000_000
    }
    #[cfg(windows)]
    {
        // SAFETY: no arguments, no pointer.
        unsafe { windows::Win32::System::SystemInformation::GetTickCount64() as i64 }
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        use std::sync::OnceLock;
        use std::time::Instant;
        static START: OnceLock<Instant> = OnceLock::new();
        START.get_or_init(Instant::now).elapsed().as_millis() as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(kind: Kind, key: &str) -> Shown {
        Shown { kind, key: key.to_string() }
    }

    #[test]
    fn nothing_on_the_island() {
        let r = CardRules::default();
        assert!(!r.interactive() && !r.accepts(None, 100_000) && !r.accepts(Some(&shown(Kind::Pair, "483291|Desk PC")), 100_000));
    }

    #[test]
    fn a_card_in_front_of_the_user_is_never_replaced_by_another_flows() {
        let (pair, other_pair, offer, result) = (shown(Kind::Pair, "483291|Desk PC"), shown(Kind::Pair, "111111|Old laptop"), shown(Kind::Offer, "t1"), shown(Kind::Result, "Paired|This PC and Desk PC"));
        let mut r = CardRules::default();
        assert!(r.show(pair.clone(), "pair:A", 1_000) && r.interactive());
        assert!(!r.show(other_pair, "pair:B", 2_000) && r.shown() == Some(&pair) && r.owner() == Some("pair:A"));
        assert!(!r.show(offer.clone(), "transfer:t1", 2_000) && r.shown() == Some(&pair));
        assert!(!r.show(result, "pair:B", 2_000) && r.shown() == Some(&pair));

        let mut r = CardRules::default();
        r.show(offer.clone(), "transfer:t1", 1_000);
        assert!(!r.show(pair, "pair:A", 5_000));
        assert!(!r.show(shown(Kind::Offer, "t2"), "transfer:t2", 5_000));
        assert_eq!(r.shown(), Some(&offer));
        let receiving = shown(Kind::Receiving, "t1");
        assert!(r.show(receiving.clone(), "transfer:t1", 9_000) && r.shown() == Some(&receiving));
        assert_eq!(r.changed_at(), 9_000, "a change of kind");
    }

    #[test]
    fn a_card_that_is_over_gives_way() {
        let mut r = CardRules::default();
        r.show(shown(Kind::Result, "Paired|x"), "pair:A", 1_000);
        assert!(!r.interactive());
        let offer = shown(Kind::Offer, "t1");
        assert!(r.show(offer.clone(), "transfer:t1", 2_000) && r.shown() == Some(&offer));
        assert_eq!(r.changed_at(), 2_000);
    }

    #[test]
    fn a_flow_that_ends_changes_the_card_only_if_it_is_still_its_own() {
        let pair = shown(Kind::Pair, "483291|Desk PC");
        let mut r = CardRules::default();
        r.show(pair.clone(), "pair:A", 1_000);
        assert!(!r.end("transfer:t1") && r.shown() == Some(&pair));
        assert!(r.end("pair:A") && r.shown().is_none() && !r.interactive());
        let result = shown(Kind::Result, "Paired|x");
        let mut r = CardRules::default();
        r.show(shown(Kind::Offer, "t1"), "transfer:t1", 1_000);
        assert!(!r.show(result.clone(), "pair:A", 2_000), "another flow's result does not overwrite the offer");
        assert!(r.show(result.clone(), "transfer:t1", 3_000) && r.shown() == Some(&result), "its own result does");
    }

    #[test]
    fn a_click() {
        let (pair, other_pair, offer, result) = (shown(Kind::Pair, "483291|Desk PC"), shown(Kind::Pair, "111111|Old laptop"), shown(Kind::Offer, "t1"), shown(Kind::Result, "Paired|x"));
        let mut r = CardRules::default();
        r.show(pair.clone(), "pair:A", 10_000);
        assert_eq!([r.accepts(Some(&pair), 10_000), r.accepts(Some(&pair), 10_699), r.accepts(Some(&pair), 10_700)], [false, false, true], "700 ms of quiet");
        assert_eq!([r.accepts(Some(&other_pair), 50_000), r.accepts(Some(&offer), 50_000), r.accepts(Some(&result), 50_000)], [false; 3]);
        assert_eq!([r.accepts(None, 10_100), r.accepts(None, 20_000)], [false, true], "without an identity: the current card once it has settled");
        r.show(pair.clone(), "pair:A", 30_000);
        assert!(r.accepts(Some(&pair), 30_000), "the user's own answer (same card, same kind) does not start a new quiet period");
        r.show(result.clone(), "pair:A", 40_000);
        assert_eq!([r.accepts(Some(&result), 40_300), r.accepts(Some(&result), 40_700), r.accepts(Some(&pair), 41_000)], [false, true, false]);
    }

    #[test]
    fn an_offer_is_identified_by_the_machine_and_the_transfer_id_together() {
        let (desk, laptop) = (offer_key("d1", "t1"), offer_key("l1", "t1"));
        assert_ne!(desk, laptop);
        assert_eq!(desk, offer_key("d1", "t1"));
        let (desk_offer, laptop_offer) = (shown(Kind::Offer, &desk), shown(Kind::Offer, &laptop));
        let mut r = CardRules::default();
        r.show(desk_offer.clone(), &format!("transfer:{desk}"), 1_000);
        assert!(!r.accepts(Some(&laptop_offer), 9_000));
        assert!(!r.show(laptop_offer, &format!("transfer:{laptop}"), 9_000));
        assert!(r.accepts(Some(&desk_offer), 9_000));
    }

    #[test]
    fn a_late_event_from_a_stopped_conversation_is_stale() {
        let mut g = RunGate::default();
        let first = g.begin_receive();
        assert!(g.is_receive(first) && !g.is_pair(first));
        g.stop();
        assert!(!g.is_receive(first) && g.generation() == 1);
        let second = g.begin_receive();
        assert!(second != first && g.is_receive(second) && !g.is_receive(first));
        g.end_receive();
        assert!(!g.is_receive(second), "ending the run makes its ticket stale at once");
        let third = g.begin_receive();
        assert!(!g.is_receive(second) && g.is_receive(third));
        let pair = g.begin_pair();
        g.stop();
        assert!(!g.is_pair(pair));
        let again = g.begin_pair();
        g.end_pair();
        assert!(!g.is_pair(again));
    }

    #[test]
    fn a_second_offer_is_declined_as_busy_before_any_card_can_be_taken_from_it() {
        let b = Busy::default();
        assert_eq!([b.claim("d1"), b.claim("d1")], [true, false]);
        assert!(!b.reserve_card(), "a pairing code cannot take the card while an offer is claimed and has none yet");
        assert!(b.holds("d1"));
        b.release("d1");
        assert!(!b.holds("d1"));
        assert_eq!([b.reserve_card(), b.claim("d2")], [true, false], "a pairing code reserves the card; an offer that arrives next is refused at the claim");
        b.set_card_locked(false);
        assert!(b.claim("d2"));
        let one = Busy::default();
        assert_eq!([one.claim("d1"), one.claim("d2")], [true, false]);
        one.release("d1");
        assert!(one.claim("d2"), "one transfer for the whole machine, then the next");
    }

    /// The contract's `places[]` (docs/LINK-CONTRACT.md, "One transfer for the whole machine") through the real `Busy`: its answers are the table's.
    #[test]
    fn busy_gives_the_contracts_answers_for_the_machines_one_transfer_place() {
        use crate::link::testutil::{arr, fixture, name};
        let f = fixture("flow-cases.json");
        for t in arr(&f, "places") {
            let busy = Busy::default();
            if let Some(h) = t["from"]["holder"].as_str() {
                assert!(busy.claim(h));
            }
            busy.set_card_locked(t["from"]["card"].as_bool().unwrap());
            for (i, e) in t["events"].as_array().unwrap().iter().enumerate() {
                let want = &t["out"][i];
                let granted = if let Some(c) = e.get("claim") {
                    Some(busy.claim(c.as_str().unwrap()))
                } else if let Some(r) = e.get("release") {
                    busy.release(r.as_str().unwrap());
                    None
                } else {
                    busy.set_card_locked(e["card"].as_bool().unwrap());
                    None
                };
                assert_eq!(granted, want["granted"].as_bool(), "{} step {i}", name(t));
                let holder = want["place"]["holder"].as_str();
                assert_eq!(holder.is_some_and(|h| busy.holds(h)), holder.is_some(), "{} step {i}: the holder", name(t));
            }
        }
    }

    #[test]
    fn how_many_connections_may_be_established() {
        let caps = ConnectionCaps::default();
        assert_eq!([caps.admit(0, "d1"), caps.admit(1, "d1"), caps.admit(2, "d1")], [true, true, false], "a machine gets 2, not 3");
        assert!(caps.admit(0, "d1") && caps.count() == 2, "asking again for a counted connection changes nothing");
        for (i, p) in [(3, "d2"), (4, "d2"), (5, "d3"), (6, "d3"), (7, "d4"), (8, "d4")] {
            assert!(caps.admit(i, p));
        }
        assert_eq!(caps.count(), 8);
        assert!(!caps.admit(99, "d5"), "the ninth is refused, whoever it is");
        caps.release(0);
        assert_eq!([caps.admit(100, "d1"), caps.admit(101, "d5")], [true, false]);
    }

    #[test]
    fn the_paired_map_is_read_again_but_not_in_a_loop() {
        let mut limit = ReadLimit::default();
        assert!(limit.due(1_000));
        limit.read(1_000);
        assert_eq!([limit.due(1_000), limit.due(5_999), limit.due(6_000)], [false, false, true]);
        limit.read(6_000);
        assert_eq!([limit.due(10_999), limit.due(11_000)], [false, true]);
    }

    #[test]
    fn the_clock_moves_in_whole_milliseconds() {
        let t0 = now_ms();
        std::thread::sleep(std::time::Duration::from_millis(300)); // Windows' tick (GetTickCount64) is 10 to 16 ms: the bound leaves room for it
        let dt = now_ms() - t0;
        assert!((250..600).contains(&dt), "300 ms of sleep read as {dt}");
    }
}
