// The one implementation of `Discovery` that touches the network (sub-project G2): `_notchmeow._tcp` over mDNS with the `mdns-sd` crate (pure Rust, no Avahi or Bonjour service needed; the owner
// approved the crate on 2026-10-14). The advert carries only `v`, `id` and `name`; the host name in the DNS records is made from the first eight digits of the device id, never from the
// computer's name. IPv4 only, as the listener is: IPv6 is switched off in the daemon.
//
// **The daemon exists only while something needs it.** Making a `ServiceDaemon` opens the multicast sockets and starts its thread, so it is made when the machine is first announced or the
// first search starts, and shut down when both are over: with Visible off and nobody looking at Devices or the shelf, this file holds nothing and the process has no mDNS socket.
// `scripts/link-tests/wiring.test.mjs` pins that `ServiceDaemon::new` is called only here, in `daemon()`.
//
// **A daemon that dies is made again (G2b).** `mdns-sd` runs the daemon on its own thread; if that thread ends, the machine list would go stale and this machine would stop being announced. Every
// daemon made here has a watch thread asleep in `recv()` on the daemon's monitor channel, which closes when the daemon's thread ends (a search's own channel closing says the same). The watch
// asks `restart.rs` for a wait (1 s, 5 s, 30 s, then every minute), empties the list on screen, and a one-shot wait (a `Condvar`, no polling) makes the daemon, announces again what was announced
// and searches again with what `browse` was given. Nothing is done when nothing is announced or searched: `release` cancels the wait and the wish.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::ThreadId;
use std::time::{Duration, Instant};

use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};

use super::discovery::{Discovery, Found, OnResults, SERVICE_TYPE};
use super::frames::{parse_txt, Advert, OwnId, Txt};
use super::restart::Restarter;

// What the user is told when the network says no. Fixed sentences: nothing the crate or the system says (it can hold an address or a name) goes to the screen or the log.
const CANNOT_ANNOUNCE: &str = "This computer could not be announced on the network.";
const CANNOT_SEARCH: &str = "Other computers could not be searched for on the network.";

#[derive(Default)]
struct Inner {
    daemon: Option<ServiceDaemon>,
    /// What this machine announces, while it does: the full name (to unregister) and the record (to announce it again on a fresh daemon).
    advertised: Option<(String, ServiceInfo)>,
    /// While a search runs: the gate its waiting thread hands results through.
    browsing: Option<Arc<Gate>>,
    /// What `browse` was given while a search is wanted: this machine's id and the callback, so that a daemon made again can search again. `stop_browsing` takes it away.
    search: Option<(String, OnResults)>,
    /// The number of the daemon in `daemon`. A death reported by an older daemon (one we replaced or shut down) is not a death.
    epoch: u64,
    /// The rule that decides how long to wait before a daemon is made again.
    restarter: Restarter,
    /// The number of the restart wait that is allowed to run; a wait that finds another number was cancelled.
    wait: u64,
}

/// The state, the signal that wakes a restart wait early (to cancel it) and the clock the restart rule is fed with.
struct Shared {
    inner: Mutex<Inner>,
    wake: Condvar,
    born: Instant,
}

impl Shared {
    fn now_ms(&self) -> u64 {
        self.born.elapsed().as_millis() as u64
    }
}

pub struct Mdns {
    shared: Arc<Shared>,
}

impl Default for Mdns {
    fn default() -> Mdns {
        Mdns { shared: Arc::new(Shared { inner: Mutex::new(Inner::default()), wake: Condvar::new(), born: Instant::now() }) }
    }
}

/// Where a search hands its results up. A result is handed up only while the gate is open, and closing the gate waits for a result that is being handed up at that moment, so **no result is
/// delivered after `stop_browsing` has returned**. The gate has its own lock, not the one of `Inner`: the service's callback may call `stop_browsing` (or anything else of `Mdns`) from inside a
/// delivery, and `wait_idle` knows that thread and does not wait for itself.
struct Gate {
    open: AtomicBool,
    /// Held while a result is handed up.
    running: Mutex<()>,
    /// The thread that is handing up a result now.
    runner: Mutex<Option<ThreadId>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Gate {
    fn new() -> Gate {
        Gate { open: AtomicBool::new(true), running: Mutex::new(()), runner: Mutex::new(None) }
    }

    /// Hands a result up through `f`, unless the gate is closed (then false, and `f` is not called).
    fn deliver(&self, f: impl FnOnce()) -> bool {
        let _run = lock(&self.running);
        if !self.open.load(Ordering::SeqCst) {
            return false;
        }
        *lock(&self.runner) = Some(std::thread::current().id());
        f();
        *lock(&self.runner) = None;
        true
    }

    /// Hands up one last result through `f` whether or not the gate is closed (after `shut`, so that nothing the search thread still holds follows it). Waits for a result being handed up now.
    fn deliver_last(&self, f: impl FnOnce()) {
        let _run = lock(&self.running);
        *lock(&self.runner) = Some(std::thread::current().id());
        f();
        *lock(&self.runner) = None;
    }

    /// No result is handed up from now on.
    fn shut(&self) {
        self.open.store(false, Ordering::SeqCst);
    }

    /// False once `stop_browsing` has closed the gate: the only way a search is stopped by us.
    fn is_open(&self) -> bool {
        self.open.load(Ordering::SeqCst)
    }

    /// Waits for the result that is being handed up, if any, unless this is the thread handing it up.
    fn wait_idle(&self) {
        if *lock(&self.runner) == Some(std::thread::current().id()) {
            return;
        }
        drop(lock(&self.running));
    }
}

/// This machine's advert as a service record: the instance is the first twelve digits of the device id, the DNS host name the first eight (never the computer's name), the TXT record the three
/// keys `v`, `id` and `name`. `ip` is `""` for the real advert (the daemon fills the addresses in), an address in the tests.
fn service(id: &str, name: &str, port: u16, ip: &str) -> Result<ServiceInfo, String> {
    let instance = id.get(..12).unwrap_or(id);
    let host = format!("notchmeow-{}.local.", id.get(..8).unwrap_or(id));
    let mut txt = HashMap::new();
    txt.insert("v".to_string(), "1".to_string());
    txt.insert("id".to_string(), id.to_string());
    txt.insert("name".to_string(), name.to_string());
    ServiceInfo::new(SERVICE_TYPE, instance, &host, ip, port, txt).map_err(|_| CANNOT_ANNOUNCE.to_string())
}

/// A resolved service as a machine to list: the advert must pass the contract's checks (version, id, name, not this machine's own id) and there must be an IPv4 address to connect to. With
/// several, the lowest is taken, so the same advert always gives the same address. A loopback, unspecified or multicast address is never one: a host on the network could name one to aim a Pair or
/// Send click at this machine itself, or at nobody.
fn found(info: &ServiceInfo, own_id: &str) -> Option<Found> {
    let get = |k: &str| info.get_property_val_str(k);
    let advert: Advert = parse_txt(&Txt { v: get("v"), id: get("id"), name: get("name") }, OwnId::Id(own_id)).ok()?;
    let mut v4: Vec<Ipv4Addr> = info.get_addresses().iter().filter_map(|a| if let IpAddr::V4(v) = a { Some(*v) } else { None }).filter(|v| !v.is_loopback() && !v.is_unspecified() && !v.is_multicast()).collect();
    v4.sort_unstable();
    Some(Found { advert, addr: SocketAddr::new(IpAddr::V4(*v4.first()?), info.get_port()) })
}

/// The list handed up, in a fixed order (by name, then id, then address), so that the same machines always give the same list.
fn listing(machines: &HashMap<String, Found>) -> Vec<Found> {
    let mut list: Vec<Found> = machines.values().cloned().collect();
    list.sort_by(|a, b| (&a.advert.name, &a.advert.id, a.addr).cmp(&(&b.advert.name, &b.advert.id, b.addr)));
    list
}

/// What one search does with the daemon's events until the search or the daemon ends: keeps the machines seen and hands the whole list up, through the gate, every time it changes. True when
/// the search ended by itself (the events ran out, or the daemon said `SearchStopped` because it was shut down or replaced), false when `stop_browsing` stopped it. Who ended it is decided by the
/// gate, which only `stop_browsing` closes, never by the event: the daemon says `SearchStopped` in both cases.
fn run_search(events: impl Iterator<Item = ServiceEvent>, own_id: &str, gate: &Gate, on_results: &OnResults) -> bool {
    let mut machines: HashMap<String, Found> = HashMap::new();
    for event in events {
        match event {
            ServiceEvent::ServiceResolved(info) => match found(&info, own_id) {
                Some(f) => {
                    machines.insert(info.get_fullname().to_string(), f);
                }
                // An advert that does not pass the contract's checks (version, id, name, this machine's own id) is not listed.
                None => {
                    machines.remove(info.get_fullname());
                }
            },
            ServiceEvent::ServiceRemoved(_, full) => {
                machines.remove(&full);
            }
            ServiceEvent::SearchStopped(_) => return gate.is_open(),
            _ => continue,
        }
        if !gate.deliver(|| on_results(listing(&machines))) {
            return false;
        }
    }
    gate.is_open()
}

/// A daemon that could not be switched to IPv4 only (its IPv6 sockets would stay open) is shut down and not used: this fails closed.
fn ipv4_only<D>(daemon: D, switched_off: bool, shut_down: impl FnOnce(&D)) -> Option<D> {
    if switched_off {
        Some(daemon)
    } else {
        shut_down(&daemon);
        None
    }
}

impl Mdns {
    pub fn new() -> Mdns {
        Mdns::default()
    }

    /// The daemon, made on first use. IPv6 is switched off: the advert and the listener are IPv4, and a daemon that cannot be switched is not used. A daemon that cannot be watched cannot be repaired
    /// and is not used either. `fresh` drops the daemon there is (one that died on its own) and the search that ran on it, and makes another, which announces again what this machine announced.
    fn daemon(shared: &Arc<Shared>, inner: &mut Inner, fresh: bool) -> Option<ServiceDaemon> {
        if !fresh {
            if let Some(d) = &inner.daemon {
                return Some(d.clone());
            }
        }
        // The new daemon is made before the old state is touched: if it cannot be made, the old daemon stays as it is and its own watch reports its death as usual.
        let d = ServiceDaemon::new().ok()?;
        let d = ipv4_only(d.clone(), d.disable_interface(IfKind::IPv6).is_ok(), |d| {
            let _ = d.shutdown();
        })?;
        let Ok(events) = d.monitor() else {
            let _ = d.shutdown();
            return None;
        };
        if fresh {
            if let Some(old) = inner.daemon.take() {
                let _ = old.shutdown();
            }
            if let Some(dead) = inner.browsing.take() {
                dead.shut();
            }
        }
        if let Some((_, info)) = &inner.advertised {
            let _ = d.register(info.clone());
        }
        inner.epoch += 1;
        inner.daemon = Some(d.clone());
        inner.restarter.started(shared.now_ms());
        Mdns::arm(shared, inner, None); // a restart that was waiting is not needed any more
        let (watch, epoch) = (shared.clone(), inner.epoch);
        // Asleep in `recv` (nothing polls): the channel closes when the daemon's thread ends, whoever ended it (`died` tells our own shutdowns from the rest).
        std::thread::spawn(move || {
            for _ in events.iter() {}
            Mdns::died(&watch, epoch);
        });
        Some(d)
    }

    /// Runs `op` on the daemon. If it fails (a daemon that died on its own), the daemon is dropped and `op` is tried once more on a fresh one; `None` when that fails too.
    fn run<T>(shared: &Arc<Shared>, inner: &mut Inner, op: impl Fn(&ServiceDaemon) -> mdns_sd::Result<T>) -> Option<T> {
        let d = Mdns::daemon(shared, inner, false)?;
        if let Ok(v) = op(&d) {
            return Some(v);
        }
        op(&Mdns::daemon(shared, inner, true)?).ok()
    }

    /// Nothing announced and nothing searched: the daemon is shut down, the wish is taken away and a restart that was waiting is cancelled.
    fn release(shared: &Arc<Shared>, inner: &mut Inner) {
        if inner.advertised.is_none() && inner.search.is_none() {
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
            inner.restarter.set_wanted(false);
            Mdns::arm(shared, inner, None);
        }
    }

    /// Starts the search `inner.search` describes on the daemon (made if need be). True when it runs.
    fn start_search(shared: &Arc<Shared>, inner: &mut Inner) -> bool {
        let Some((own, on_results)) = inner.search.clone() else { return false };
        let Some(receiver) = Mdns::run(shared, inner, |d| d.browse(SERVICE_TYPE)) else { return false };
        let gate = Arc::new(Gate::new());
        inner.browsing = Some(gate.clone());
        let (watch, epoch) = (shared.clone(), inner.epoch);
        // One thread that waits on the daemon's channel (it sleeps in `recv`, nothing polls) and ends when the search is stopped or the daemon is gone.
        std::thread::spawn(move || {
            if run_search(receiver.iter(), &own, &gate, &on_results) {
                // The search ended by itself: the daemon is gone (or was replaced, which `died` sees by its number).
                Mdns::died(&watch, epoch);
            }
        });
        true
    }

    /// The daemon of number `epoch` ended. Ignored if we ended it ourselves (it was replaced or released) or if this death was already seen. Otherwise the dead handle is dropped, the list on screen
    /// (now stale) is emptied, and, if an advert or a search is wanted, a restart is scheduled by the rule.
    fn died(shared: &Arc<Shared>, epoch: u64) {
        let (stale, clear) = {
            let mut inner = lock(&shared.inner);
            if inner.epoch != epoch || inner.daemon.is_none() {
                return;
            }
            if let Some(d) = inner.daemon.take() {
                let _ = d.shutdown();
            }
            let wanted = inner.advertised.is_some() || inner.search.is_some();
            inner.restarter.set_wanted(wanted);
            let wait = inner.restarter.died(shared.now_ms());
            Mdns::arm(shared, &mut inner, wait);
            (inner.browsing.take(), inner.search.as_ref().map(|(_, on)| on.clone()))
        };
        // Outside the lock (the callback may call into `Mdns`): the machines that were listed are no longer known to be there.
        // The gate is shut first: events still queued from the dead daemon must not be handed up after the empty list.
        if let Some(gate) = stale {
            gate.shut();
            if let Some(on) = clear {
                gate.deliver_last(|| on(Vec::new()));
            }
        }
    }

    /// Cancels the restart wait that is pending (if any) and, with `Some(ms)`, starts a new one: a thread asleep on the `Condvar` for at most `ms`, which makes the daemon again when the time is up and
    /// does nothing if it was cancelled meanwhile. No timer, no polling: the thread ends the moment it is cancelled.
    fn arm(shared: &Arc<Shared>, inner: &mut Inner, wait_ms: Option<u64>) {
        inner.wait += 1;
        shared.wake.notify_all();
        let Some(ms) = wait_ms else { return };
        let (number, shared) = (inner.wait, shared.clone());
        std::thread::spawn(move || {
            let begun = Instant::now();
            let mut inner = lock(&shared.inner);
            loop {
                if inner.wait != number {
                    return;
                }
                let left = Duration::from_millis(ms).saturating_sub(begun.elapsed());
                if left.is_zero() {
                    break;
                }
                inner = shared.wake.wait_timeout(inner, left).unwrap_or_else(|e| e.into_inner()).0;
            }
            Mdns::restart(&shared, &mut inner);
        });
    }

    /// The wait is over: if an advert or a search is still wanted, makes the daemon (which announces again) and starts the search again; if that fails, the rule gives the next wait.
    fn restart(shared: &Arc<Shared>, inner: &mut Inner) {
        if inner.advertised.is_none() && inner.search.is_none() {
            inner.restarter.set_wanted(false);
            return;
        }
        let up = Mdns::daemon(shared, inner, false).is_some() && (inner.search.is_none() || inner.browsing.is_some() || Mdns::start_search(shared, inner));
        if !up {
            let wait = inner.restarter.failed_restart();
            Mdns::arm(shared, inner, wait);
        }
    }
}

impl Discovery for Mdns {
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String> {
        let info = service(id, name, port, "")?.enable_addr_auto();
        let full = info.get_fullname().to_string();
        let mut inner = lock(&self.shared.inner);
        if let (Some(d), Some((old, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&old);
        }
        match Mdns::run(&self.shared, &mut inner, |d| d.register(info.clone())) {
            Some(()) => {
                inner.advertised = Some((full, info));
                // A fresh daemon (the old one had died) has no search yet: start the one that is wanted.
                if inner.search.is_some() && inner.browsing.is_none() && !Mdns::start_search(&self.shared, &mut inner) {
                    inner.restarter.set_wanted(true);
                    let wait = inner.restarter.failed_restart();
                    Mdns::arm(&self.shared, &mut inner, wait);
                }
                Ok(())
            }
            None => {
                Mdns::release(&self.shared, &mut inner);
                Err(CANNOT_ANNOUNCE.to_string())
            }
        }
    }

    fn stop_advertising(&self) {
        let mut inner = lock(&self.shared.inner);
        if let (Some(d), Some((full, _))) = (inner.daemon.clone(), inner.advertised.take()) {
            let _ = d.unregister(&full);
        }
        Mdns::release(&self.shared, &mut inner);
    }

    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        let mut inner = lock(&self.shared.inner);
        if inner.search.is_some() {
            return Ok(());
        }
        inner.search = Some((own_id.to_string(), on_results));
        if Mdns::start_search(&self.shared, &mut inner) {
            return Ok(());
        }
        inner.search = None;
        Mdns::release(&self.shared, &mut inner);
        Err(CANNOT_SEARCH.to_string())
    }

    fn stop_browsing(&self) {
        let gate = {
            let mut inner = lock(&self.shared.inner);
            inner.search = None;
            let gate = inner.browsing.take();
            if let Some(g) = &gate {
                g.shut();
                if let Some(d) = &inner.daemon {
                    let _ = d.stop_browse(SERVICE_TYPE);
                }
            }
            Mdns::release(&self.shared, &mut inner);
            gate
        };
        // Outside the lock of `Inner`: a result being handed up may be in the service's callback, which can call into `Mdns`.
        if let Some(g) = gate {
            g.wait_idle();
        }
    }
}

// No test here touches the network: no daemon, no multicast socket. A `ServiceInfo` is only data.
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::time::Duration;

    const ID: &str = "0123456789abcdef0123456789abcdef";
    const OTHER: &str = "fedcba9876543210fedcba9876543210";

    #[test]
    fn the_advert_carries_the_three_keys_and_a_host_name_made_from_the_id() {
        let info = service(ID, "Sam's MacBook Pro", 4242, "").unwrap();
        assert_eq!(info.get_type(), SERVICE_TYPE);
        assert_eq!(info.get_fullname(), "0123456789ab._notchmeow._tcp.local.");
        assert_eq!(info.get_hostname(), "notchmeow-01234567.local.");
        assert_eq!(info.get_port(), 4242);
        let mut keys: Vec<&str> = info.get_properties().iter().map(|p| p.key()).collect();
        keys.sort_unstable();
        assert_eq!(keys, ["id", "name", "v"]);
        assert_eq!(info.get_property_val_str("v"), Some("1"));
        assert_eq!(info.get_property_val_str("id"), Some(ID));
        assert_eq!(info.get_property_val_str("name"), Some("Sam's MacBook Pro"));
        assert!(!info.get_hostname().contains("Sam") && !info.get_fullname().contains("Sam"), "the computer's name is only in the TXT record, as the user chose it");
    }

    #[test]
    fn a_resolved_advert_comes_back_as_the_machine_that_made_it() {
        let found = found(&service(ID, "Desk PC", 4242, "192.168.7.42").unwrap(), OTHER).unwrap();
        assert_eq!(found.advert, Advert { id: ID.into(), name: "Desk PC".into() });
        assert_eq!(found.addr, "192.168.7.42:4242".parse::<SocketAddr>().unwrap());
    }

    #[test]
    fn an_advert_that_does_not_pass_is_not_listed() {
        assert!(found(&service(ID, "Desk PC", 4242, "192.168.7.42").unwrap(), ID).is_none(), "this machine's own advert");
        assert!(found(&service(ID, "Desk PC", 4242, "").unwrap(), OTHER).is_none(), "no address to connect to");
        assert!(found(&service(ID, "Desk PC", 4242, "fe80::1").unwrap(), OTHER).is_none(), "IPv6 only: the listener is IPv4");
        assert!(found(&service(ID, " Desk PC", 4242, "192.168.7.42").unwrap(), OTHER).is_none(), "a name that does not pass");
        assert!(found(&service("not-an-id", "Desk PC", 4242, "192.168.7.42").unwrap(), OTHER).is_none(), "an id that does not pass");
        let wrong_version = ServiceInfo::new(SERVICE_TYPE, "x", "h.local.", "192.168.7.42", 1, [("v", "2"), ("id", ID), ("name", "Desk PC")].as_slice()).unwrap();
        assert!(found(&wrong_version, OTHER).is_none(), "another version");
        let no_name = ServiceInfo::new(SERVICE_TYPE, "x", "h.local.", "192.168.7.42", 1, [("v", "1"), ("id", ID)].as_slice()).unwrap();
        assert!(found(&no_name, OTHER).is_none(), "no name");
    }

    #[test]
    fn an_address_a_lan_host_could_use_to_aim_a_click_at_this_machine_is_not_listed() {
        for ip in ["127.0.0.1", "0.0.0.0", "224.0.0.251", "127.0.0.1,0.0.0.0,239.1.2.3"] {
            assert!(found(&service(ID, "Desk PC", 4242, ip).unwrap(), OTHER).is_none(), "{ip}");
        }
        let f = found(&service(ID, "Desk PC", 4242, "127.0.0.1,224.0.0.251,192.168.7.42").unwrap(), OTHER).unwrap();
        assert_eq!(f.addr, "192.168.7.42:4242".parse::<SocketAddr>().unwrap(), "the usable address is kept");
    }

    /// A valid, distinct device id per number.
    fn id(n: u8) -> String {
        format!("{n:02x}").repeat(16)
    }

    fn resolved(n: u8, name: &str, ip: &str) -> ServiceEvent {
        ServiceEvent::ServiceResolved(service(&id(n), name, 4242, ip).unwrap())
    }

    /// Runs a search over made-up events and gives back the lists that were handed up.
    fn lists(events: Vec<ServiceEvent>, own: &str) -> Vec<Vec<Found>> {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let s = seen.clone();
        run_search(events.into_iter(), own, &Gate::new(), &(Arc::new(move |l| s.lock().unwrap().push(l)) as OnResults));
        let out = seen.lock().unwrap().clone();
        out
    }

    #[test]
    fn with_several_ipv4_addresses_the_lowest_is_always_the_one_listed() {
        for ips in ["192.168.7.42,10.0.0.5,172.16.0.9", "172.16.0.9,192.168.7.42,10.0.0.5", "10.0.0.5,fe80::1,192.168.7.42"] {
            let f = found(&service(ID, "Desk PC", 4242, ips).unwrap(), OTHER).unwrap();
            assert_eq!(f.addr, "10.0.0.5:4242".parse::<SocketAddr>().unwrap(), "{ips}");
        }
    }

    #[test]
    fn the_list_handed_up_is_in_a_fixed_order_whatever_order_the_machines_came_in() {
        let (a, b, c) = (resolved(1, "Desk PC", "10.0.0.1"), resolved(2, "Old netbook", "10.0.0.2"), resolved(3, "Desk PC", "10.0.0.3"));
        let again = |n, name: &str, ip: &str| resolved(n, name, ip);
        let first = lists(vec![a, b, c], OTHER).pop().unwrap();
        let second = lists(vec![again(3, "Desk PC", "10.0.0.3"), again(1, "Desk PC", "10.0.0.1"), again(2, "Old netbook", "10.0.0.2")], OTHER).pop().unwrap();
        assert_eq!(first, second);
        let order: Vec<(String, String)> = first.iter().map(|f| (f.advert.name.clone(), f.advert.id.clone())).collect();
        assert_eq!(order, [("Desk PC".into(), id(1)), ("Desk PC".into(), id(3)), ("Old netbook".into(), id(2))], "by name, then id");
    }

    #[test]
    fn a_removed_or_unlisted_machine_leaves_the_list_and_a_closed_channel_is_reported() {
        let gone = ServiceEvent::ServiceRemoved(SERVICE_TYPE.into(), service(&id(1), "x", 1, "").unwrap().get_fullname().to_string());
        let got = lists(vec![resolved(1, "Desk PC", "10.0.0.1"), resolved(2, "Old netbook", "10.0.0.2"), gone, resolved(3, "Studio laptop", "")], OTHER);
        assert_eq!(got.last().unwrap().len(), 1, "the removed one is gone, the one without an address was never listed");
        let run = |events: Vec<ServiceEvent>, gate: &Gate| run_search(events.into_iter(), OTHER, gate, &(Arc::new(|_| {}) as OnResults));
        let stopped = || vec![ServiceEvent::SearchStopped(SERVICE_TYPE.into())];
        assert!(run(vec![], &Gate::new()), "the channel closed by itself: the daemon is gone");
        // The daemon says SearchStopped when it is shut down too: only the gate, which only `stop_browsing` closes, tells who ended the search.
        assert!(run(stopped(), &Gate::new()), "SearchStopped with the gate open: it ended by itself (the daemon was replaced or released)");
        let shut = Gate::new();
        shut.shut();
        assert!(!run(stopped(), &shut), "SearchStopped with the gate closed: we stopped it");
        assert!(!run(vec![], &shut), "and a channel that closes after we stopped it is not an end by itself");
    }

    #[test]
    fn nothing_is_handed_up_once_the_search_is_stopped() {
        let gate = Gate::new();
        let count = Arc::new(AtomicUsize::new(0));
        let c = count.clone();
        let on: OnResults = Arc::new(move |_| {
            c.fetch_add(1, Ordering::SeqCst);
        });
        gate.shut();
        gate.wait_idle();
        run_search(vec![resolved(1, "Desk PC", "10.0.0.1")].into_iter(), OTHER, &gate, &on);
        assert_eq!(count.load(Ordering::SeqCst), 0);
    }

    // `stop_browsing` returns only when a result that is being handed up has been handed, and nothing follows it.
    #[test]
    fn stopping_waits_for_a_result_in_flight_and_none_follows() {
        let gate = Arc::new(Gate::new());
        let count = Arc::new(AtomicUsize::new(0));
        let (entered_tx, entered_rx) = std::sync::mpsc::channel::<()>();
        let (release_tx, release_rx) = std::sync::mpsc::channel::<()>();
        let release_rx = Mutex::new(release_rx);
        let c = count.clone();
        let on: OnResults = Arc::new(move |_| {
            c.fetch_add(1, Ordering::SeqCst);
            let _ = entered_tx.send(());
            let _ = release_rx.lock().unwrap().recv_timeout(Duration::from_secs(10));
        });
        let g = gate.clone();
        let search = std::thread::spawn(move || run_search(vec![resolved(1, "Desk PC", "10.0.0.1"), resolved(2, "Old netbook", "10.0.0.2")].into_iter(), OTHER, &g, &on));
        entered_rx.recv_timeout(Duration::from_secs(10)).expect("a result is being handed up");
        let (done_tx, done_rx) = std::sync::mpsc::channel::<()>();
        let g = gate.clone();
        let stopper = std::thread::spawn(move || {
            g.shut();
            g.wait_idle();
            let _ = done_tx.send(());
        });
        assert!(done_rx.recv_timeout(Duration::from_millis(300)).is_err(), "stopping waits for the result in flight");
        release_tx.send(()).unwrap();
        done_rx.recv_timeout(Duration::from_secs(10)).expect("and returns once it was handed");
        stopper.join().unwrap();
        search.join().unwrap();
        assert_eq!(count.load(Ordering::SeqCst), 1, "the second result was not handed up");
    }

    // The service's callback may itself stop the search: that must not wait for itself.
    #[test]
    fn a_callback_may_stop_the_search_it_is_called_from() {
        let gate = Arc::new(Gate::new());
        let g = gate.clone();
        let on: OnResults = Arc::new(move |_| {
            g.shut();
            g.wait_idle();
        });
        let (done_tx, done_rx) = std::sync::mpsc::channel::<()>();
        let g = gate.clone();
        std::thread::spawn(move || {
            run_search(vec![resolved(1, "Desk PC", "10.0.0.1"), resolved(2, "Old netbook", "10.0.0.2")].into_iter(), OTHER, &g, &on);
            let _ = done_tx.send(());
        });
        done_rx.recv_timeout(Duration::from_secs(10)).expect("no deadlock");
    }

    // A daemon whose IPv6 switch-off failed would listen on IPv6 sockets: it is shut down and not used.
    #[test]
    fn a_daemon_that_could_not_be_switched_to_ipv4_only_is_shut_down_and_not_used() {
        let shut = std::cell::Cell::new(0);
        assert_eq!(ipv4_only(7, true, |_| shut.set(shut.get() + 1)), Some(7));
        assert_eq!(shut.get(), 0);
        assert_eq!(ipv4_only(7, false, |_| shut.set(shut.get() + 1)), None);
        assert_eq!(shut.get(), 1, "shut down");
    }

    #[test]
    fn nothing_is_made_until_something_is_announced_or_searched() {
        let m = Mdns::new();
        assert!(m.shared.inner.lock().unwrap().daemon.is_none(), "a new Mdns holds no daemon");
        m.stop_advertising();
        m.stop_browsing();
        assert!(m.shared.inner.lock().unwrap().daemon.is_none(), "stopping what never started makes nothing");
    }

    /// Waits (a test may poll) until the state is held by `Mdns` alone, i.e. until every thread that borrowed it has ended.
    fn threads_ended(m: &Mdns) -> bool {
        let end = Instant::now() + Duration::from_secs(10);
        while Arc::strong_count(&m.shared) > 1 && Instant::now() < end {
            std::thread::sleep(Duration::from_millis(10));
        }
        Arc::strong_count(&m.shared) == 1
    }

    #[test]
    fn a_restart_wait_that_is_cancelled_ends_its_thread_at_once() {
        let m = Mdns::new();
        {
            let mut inner = lock(&m.shared.inner);
            Mdns::arm(&m.shared, &mut inner, Some(600_000));
            assert_eq!(Arc::strong_count(&m.shared), 2, "the wait holds the state");
            Mdns::arm(&m.shared, &mut inner, None);
        }
        assert!(threads_ended(&m), "a cancelled wait ends without waiting its ten minutes");
    }

    #[test]
    fn a_restart_wait_that_runs_out_with_nothing_wanted_makes_nothing() {
        let m = Mdns::new();
        Mdns::arm(&m.shared, &mut lock(&m.shared.inner), Some(20));
        assert!(threads_ended(&m), "the wait ran out and ended");
        let inner = lock(&m.shared.inner);
        assert!(inner.daemon.is_none() && inner.browsing.is_none(), "no daemon, no socket: nothing was wanted");
    }

    #[test]
    fn the_last_empty_list_goes_up_after_the_gate_is_shut_and_nothing_follows_it() {
        let gate = Gate::new();
        gate.shut();
        let sent = std::cell::Cell::new(false);
        gate.deliver_last(|| sent.set(true));
        assert!(sent.get(), "the empty list is handed up through a shut gate");
        assert!(!gate.deliver(|| panic!("a listing from the dead daemon must not follow")), "a normal delivery after it is refused");
    }

    #[test]
    fn a_death_nobody_can_attribute_to_the_daemon_we_hold_is_ignored() {
        let m = Mdns::new();
        Mdns::died(&m.shared, 0); // no daemon at all: our own shutdown, or a death already seen
        Mdns::died(&m.shared, 7);
        let inner = lock(&m.shared.inner);
        assert_eq!(inner.wait, 0, "no restart was scheduled");
        assert_eq!(Arc::strong_count(&m.shared), 1);
    }

    // The next two open a real mDNS daemon (multicast sockets), which no other test does: run them by hand, `cargo test -p notchmeow link::mdns -- --ignored`.
    #[test]
    #[ignore = "opens a real mDNS daemon"]
    fn a_daemon_that_ends_closes_the_channel_the_watch_thread_sleeps_in() {
        let d = ServiceDaemon::new().unwrap();
        let events = d.monitor().unwrap();
        d.shutdown().unwrap();
        let (done, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for _ in events.iter() {}
            let _ = done.send(());
        });
        rx.recv_timeout(Duration::from_secs(10)).expect("the monitor channel closes when the daemon's thread ends");
    }

    #[test]
    #[ignore = "opens a real mDNS daemon"]
    fn a_daemon_that_dies_is_made_again_and_stops_when_nothing_is_wanted() {
        let m = Mdns::new();
        m.advertise(ID, "Desk PC", 4242).unwrap();
        let (epoch, daemon) = {
            let inner = lock(&m.shared.inner);
            (inner.epoch, inner.daemon.clone().expect("a daemon"))
        };
        let _ = daemon.shutdown(); // the daemon ends by itself, as far as `Mdns` can tell: its slot still holds it
        let end = Instant::now() + Duration::from_secs(15);
        loop {
            {
                let inner = lock(&m.shared.inner);
                if inner.epoch > epoch && inner.daemon.is_some() {
                    break;
                }
            }
            assert!(Instant::now() < end, "no new daemon within 15 s (the first wait is one second)");
            std::thread::sleep(Duration::from_millis(100));
        }
        m.stop_advertising();
        let inner = lock(&m.shared.inner);
        assert!(inner.daemon.is_none(), "nothing wanted, nothing kept");
    }
}
