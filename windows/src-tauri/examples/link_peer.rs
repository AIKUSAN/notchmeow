// A real-protocol test peer for the link (sub-project G2), for the owner's check on real machines and for whoever tests the Mac against the PC: it runs the same `link::service` as the app,
// with the same Noise, frames and files, but with its keys in memory (a new identity each run, so each run pairs again) and a plain terminal in place of the island. Run it next to the Mac's
// Debug build (or a second PC) on the same network:
//
//     cargo run --example link_peer -- "Test peer"
//
// When mDNS is blocked (a guest Wi-Fi, a container), name the other machine yourself: it prints its own id and the address it listens on, and takes the other one's with `--peer`:
//
//     cargo run --example link_peer -- "Test peer" --bind 127.0.0.1:47001 --peer 0123...(32 hex digits)@127.0.0.1:47002/Other
//
// `--no-mdns` (with no `--peer`) keeps this peer off the network except for `--bind`: no advert and no search, so nothing reaches mDNS (the two-process check uses it).
//
// Commands, one per line: `visible`, `id`, `list`, `pair N`, `yes`, `no`, `accept`, `decline`, `send PATH N`, `cancel`, `quit`. It prints the six digits, every offer, and what was received.
// Received files go to a folder under the system's temporary folder, which it prints. It never starts on its own: nothing listens until `visible`. This file is an example and is not part of
// the app: a release build does not contain it.

use std::io::BufRead;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use notchmeow_lib::link::discovery::{Discovery, Found, OnResults};
use notchmeow_lib::link::frames::Advert;
use notchmeow_lib::link::keystore::{Keystore, MemoryStore, SecretStore};
use notchmeow_lib::link::mdns::Mdns;
use notchmeow_lib::link::service::{Config, Deps, Emit, Service, ShownView, Snapshot};

/// A machine named on the command line instead of found by mDNS: it is "seen" at once, at the address given; with no machine named, nothing is seen and nothing is announced.
struct Fixed(Option<Found>);

impl Discovery for Fixed {
    fn advertise(&self, _id: &str, _name: &str, _port: u16) -> Result<(), String> {
        Ok(())
    }
    fn stop_advertising(&self) {}
    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String> {
        if let Some(found) = self.0.as_ref().filter(|f| f.advert.id != own_id) {
            on_results(vec![found.clone()]);
        }
        Ok(())
    }
    fn stop_browsing(&self) {}
}

struct Print(Mutex<Option<Snapshot>>);

impl Emit for Print {
    fn snapshot(&self, s: &Snapshot) {
        let mut last = self.0.lock().unwrap();
        let was = last.clone();
        if was.as_ref().map(|w| (&w.card, &w.rows, &w.send_status, &w.note, &w.problem)) != Some((&s.card, &s.rows, &s.send_status, &s.note, &s.problem)) {
            if let Some(c) = &s.card {
                // Never the card's key: it holds the other machine's id.
                println!("card: {} code={:?} peer={:?} name={:?} size={:?} received={:?} title={:?} detail={:?}", c.kind, c.code, c.peer, c.name, c.size, c.received, c.title, c.detail);
            } else if was.as_ref().is_some_and(|w| w.card.is_some()) {
                println!("card: none");
            }
            if let Some(t) = &s.send_status {
                println!("send: {t}");
            }
            if let Some(n) = &s.note {
                println!("note: {n}");
            }
            if let Some(p) = &s.problem {
                println!("problem: {p}");
            }
            for (i, r) in s.rows.iter().enumerate() {
                println!("  [{i}] {} ({})", r.name, r.state);
            }
        }
        *last = Some(s.clone());
    }
    fn log(&self, line: &'static str) {
        println!("log: {line}");
    }
}

/// `ID@ADDR/NAME`: the id is 32 lower-case hex digits, the address `host:port`, the name the other machine's.
fn parse_peer(text: &str) -> Option<Found> {
    let (id, rest) = text.split_once('@')?;
    let (addr, name) = rest.split_once('/')?;
    Some(Found { advert: Advert { id: id.to_string(), name: name.to_string() }, addr: addr.parse::<SocketAddr>().ok()? })
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut name = "Test peer".to_string();
    let (mut bind, mut peer, mut no_mdns): (Option<SocketAddr>, Option<Found>, bool) = (None, None, false);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--bind" => bind = args.next().and_then(|v| v.parse().ok()),
            "--peer" => peer = args.next().and_then(|v| parse_peer(&v)),
            "--no-mdns" => no_mdns = true,
            other => name = other.to_string(),
        }
    }
    let dir = std::env::temp_dir().join(format!("notchmeow-link-peer-{}", std::process::id()));
    let folder = dir.join("received");
    std::fs::create_dir_all(&dir).expect("a folder to work in");
    let runtime = tokio::runtime::Runtime::new().expect("a runtime");
    let store: Arc<dyn SecretStore> = Arc::new(MemoryStore::default());
    let keystore = Arc::new(Keystore::new(store));
    let own_id = keystore.device_id().expect("an id in memory");
    let discovery: Arc<dyn Discovery> = match (peer.clone(), no_mdns) {
        (None, false) => Arc::new(Mdns::new()),
        (found, _) => Arc::new(Fixed(found)),
    };
    let print = Arc::new(Print(Mutex::new(None)));
    let mut cfg = Config::app(dir.join("link.json"), folder.clone(), name.clone());
    if let Some(b) = bind {
        cfg.bind = b;
    }
    let handle = runtime.handle().clone();
    let svc = Service::spawn(move |f| { handle.spawn(f); }, cfg, Deps { keystore, discovery, emit: print });
    svc.start();
    println!("NotchMeow link test peer \"{name}\", id {own_id}. Received files: {}", folder.display());
    println!("Commands: visible, id, list, pair N, yes, no, accept, decline, send PATH N, cancel, quit");
    let _guard = runtime.enter();
    // The terminal counts as Devices being open: this peer is there to be paired with.
    svc.set_devices_open(true);
    let shown = |svc: &Service| runtime.block_on(svc.snapshot()).and_then(|s| s.card).map(|c| ShownView { kind: c.kind.to_string(), key: c.key });
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        // `send PATH N`: N is the last word, so a path with spaces in it works.
        if let Some((path, n)) = line.trim().strip_prefix("send ").and_then(|rest| rest.trim().rsplit_once(' ')) {
            if let Some(r) = runtime.block_on(svc.snapshot()).and_then(|s| n.trim().parse::<usize>().ok().and_then(|i| s.rows.get(i).cloned())) {
                svc.send(vec![path.trim().into()], r.id);
            }
            continue;
        }
        let mut parts = line.trim().splitn(3, ' ');
        match (parts.next(), parts.next(), parts.next()) {
            (Some("visible"), _, _) => svc.set_visible(true),
            (Some("id"), _, _) => println!("{own_id}"),
            (Some("list"), _, _) => {
                if let Some(s) = runtime.block_on(svc.snapshot()) {
                    for (i, r) in s.rows.iter().enumerate() {
                        println!("  [{i}] {} ({})", r.name, r.state);
                    }
                }
            }
            (Some("pair"), Some(n), _) => {
                if let Some(r) = runtime.block_on(svc.snapshot()).and_then(|s| n.parse::<usize>().ok().and_then(|i| s.rows.get(i).cloned())) {
                    svc.pair(r.id);
                }
            }
            (Some("yes"), _, _) => svc.answer_pair(true, shown(&svc)),
            (Some("no"), _, _) => svc.answer_pair(false, shown(&svc)),
            (Some("accept"), _, _) => svc.respond_offer(true, shown(&svc)),
            (Some("decline"), _, _) => svc.respond_offer(false, shown(&svc)),
            (Some("cancel"), _, _) => svc.cancel_sending(),
            (Some("quit"), _, _) => break,
            _ => println!("?"),
        }
    }
}
