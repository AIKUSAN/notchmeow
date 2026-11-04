import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the link (G2) is wired on the Rust side, and what it must never do, pinned as source text. The Windows-only Rust is compiled by CI (windows-tests.yml), not here; the behaviour is
// tested by `cargo test -p notchmeow link::` (windows/scripts/cargo-linux.sh). These are the properties that no unit test can see: a thing that must not appear, and a thing that must appear once.
const read = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const linkDir = new URL("../../src-tauri/src/link/", import.meta.url);
const linkFiles = fs.readdirSync(linkDir).filter((f) => f.endsWith(".rs"));
/** A Rust file without its test module and its comments: what the program does. */
const prod = (rel) => {
  const t = read(rel);
  const i = t.search(/#\[cfg\(test\)\]\s*(pub(\(crate\))? )?mod tests/);
  const body = i < 0 ? t : t.slice(0, i);
  return body.replace(/^\s*\/\/.*$/gm, "");
};
const linkProd = linkFiles.filter((f) => f !== "conformance.rs" && f !== "testutil.rs").map((f) => [f, prod(`src/link/${f}`)]);

test("lib.rs holds the module, the commands and the service, and the settings window's hide puts Devices away", () => {
  const lib = read("src/lib.rs");
  assert.match(lib, /mod island;\npub mod link;\nmod link_cmd;\nmod log;/);
  for (const c of ["state", "set_visible", "set_name", "devices_open", "shelf_open", "pair", "answer_pair", "respond_offer", "cancel_receiving", "dismiss", "forget", "send", "cancel_sending", "reveal_result", "reveal_folder"]) {
    assert.ok(lib.includes(`            link_cmd::link_${c},\n`), `link_${c} is registered`);
  }
  assert.match(lib, /let link = link_cmd::init\(&handle\);\s*app\.manage\(link_cmd::LinkHandle\(link\.clone\(\)\)\);\s*link\.start\(\);/);
  assert.match(lib, /app\.state::<ai::AiState>\(\)\.forget_custom_key\(\);\s*\/\/[^\n]*\n\s*link_cmd::settings_hidden\(&app\);/);
});

test("the dependencies are the three the lock already holds and the two the owner approved, and nothing else is new", () => {
  const toml = read("Cargo.toml");
  const section = toml.slice(toml.indexOf("[dependencies]"), toml.indexOf("[dev-dependencies]"));
  const names = [...section.matchAll(/^([a-z0-9_-]+) = /gm)].map((m) => m[1]);
  assert.deepEqual(names.sort(), ["getrandom", "lopdf", "mdns-sd", "reqwest", "serde", "serde_json", "sha2", "snow", "tauri", "tauri-plugin-autostart", "tauri-plugin-single-instance", "tokio", "unicode-normalization", "zip"].sort());
  assert.match(section, /^snow = "0\.9"$/m);
  assert.match(section, /^mdns-sd = "0\.11"$/m);
  assert.match(section, /^tokio = \{ version = "1", features = \["net", "io-util", "sync", "time", "rt", "rt-multi-thread", "macros"\] \}$/m);
  assert.doesNotMatch(toml, /^(ring|openssl|native-tls|rustls|chacha20poly1305|x25519|curve25519|if-addrs|socket2|keyring) = .*link/m, "no second crypto stack of its own");
});

test("one-shot timers only: the only sleeps are an idle watch's, the pairing window, an offer's two minutes, the listener's watchdog and its accept back-off; no interval, no thread sleep", () => {
  const sleeps = Object.fromEntries(linkProd.map(([f, t]) => [f, (t.match(/time::sleep\(/g) ?? []).length]).filter(([, n]) => n > 0));
  assert.deepEqual(sleeps, { "channel.rs": 1, "net.rs": 2, "pair_run.rs": 1, "transfer.rs": 1 });
  for (const [f, t] of linkProd) {
    assert.doesNotMatch(t, /interval\(|thread::sleep|Instant::now\(\)\s*\+|loop \{\s*tokio::time/, f);
  }
});

test("a socket is opened in net.rs and the multicast daemon in mdns.rs, each once", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/TcpListener::bind/), ["net.rs"]);
  assert.deepEqual(where(/UdpSocket/), []);
  assert.deepEqual(where(/ServiceDaemon::new\(\)/), ["mdns.rs"]);
  assert.deepEqual(where(/std::thread::spawn/), ["mdns.rs"], "the threads are the daemon's watch, the browser's and a restart wait's, all of them asleep");
  assert.equal((prod("src/link/mdns.rs").match(/ServiceDaemon::new\(\)/g) ?? []).length, 1);
});

test("a dead mDNS daemon is made again by a bounded rule, only while something is announced or searched, and without polling (G2b)", () => {
  const m = prod("src/link/mdns.rs");
  const r = prod("src/link/restart.rs");
  assert.equal((m.match(/std::thread::spawn/g) ?? []).length, 3, "the daemon's watch, the browser's, a restart wait's");
  assert.equal((m.match(/\.monitor\(\)/g) ?? []).length, 1, "every daemon is watched, in daemon()");
  assert.equal((m.match(/wake\.wait_timeout\(/g) ?? []).length, 1, "the one wait is a Condvar wait that cancelling wakes");
  assert.doesNotMatch(m, /thread::sleep|recv_timeout|try_recv|interval\(|loop \{\s*std::thread/, "nothing polls");
  assert.match(m, /restarter\.died\(shared\.now_ms\(\)\)/, "a death asks the rule");
  assert.match(m, /fn restart\(shared: &Arc<Shared>, inner: &mut Inner\) \{\s*if inner\.advertised\.is_none\(\) && inner\.search\.is_none\(\) \{\s*inner\.restarter\.set_wanted\(false\);\s*return;/, "nothing is made again when nothing is wanted");
  assert.match(m, /fn release\(shared: &Arc<Shared>, inner: &mut Inner\) \{\s*if inner\.advertised\.is_none\(\) && inner\.search\.is_none\(\) \{[^}]*\}\s*inner\.restarter\.set_wanted\(false\);\s*Mdns::arm\(shared, inner, None\);/, "releasing cancels the wish and the wait");
  const died = m.slice(m.indexOf("fn died("), m.indexOf("fn arm("));
  assert.match(died, /gate\.shut\(\);\s*if let Some\(on\) = clear \{\s*gate\.deliver_last\(/, "the gate is shut before the empty list goes up, so nothing queued from the dead daemon follows it");
  assert.match(m, /if inner\.epoch != epoch \|\| inner\.daemon\.is_none\(\) \{\s*return;/, "a daemon we replaced or released is not a death");
  const table = (re, text) => text.match(re)?.[1].replaceAll("_", "").split(",").map((s) => Number(s.trim()));
  assert.deepEqual(table(/DELAYS_MS: \[u64; 3\] = \[([^\]]+)\]/, r), [1000, 5000, 30000]);
  assert.match(r, /STEADY_MS: u64 = 60_000/);
  assert.match(r, /STABLE_MS: u64 = 60_000/);
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/LinkRestart.swift", import.meta.url), "utf8");
  assert.deepEqual(table(/static let delaysMs = \[([^\]]+)\]/, swift), [1000, 5000, 30000], "the Mac's table is this one");
  assert.match(swift, /static let steadyMs = 60_000/);
  assert.match(swift, /static let stableMs = 60_000/);
});

test("nothing listens before Visible: the listener starts in one place, and that place is reached only when the machine is visible", () => {
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/Listener::start\(/g) ?? []).length, 1);
  assert.match(svc, /async fn start_listening\(&mut self\) \{\s*if self\.listener\.is_some\(\) \{\s*return;\s*\}/);
  const calls = [...svc.matchAll(/self\.start_listening\(\)\.await;/g)].length;
  assert.equal(calls, 3, "start (guarded), set_visible, devices open (guarded)");
  assert.match(svc, /if self\.settings\.visible \{\s*self\.reload_peers\(\);\s*self\.start_listening\(\)\.await;\s*\}/, "a launch reads the credential store only when the machine is visible");
  assert.match(svc, /if self\.settings\.visible && !self\.listening \{\s*self\.start_listening\(\)\.await;/);
  assert.match(svc, /if on \{\s*self\.reload_peers\(\);\s*self\.start_listening\(\)\.await;/);
  assert.match(svc, /fn start_browser\(&mut self\) \{\s*if !self\.looking\(\) \|\| !self\.settings\.visible \{/, "the browser also needs Visible and someone looking");
  assert.match(read("src/link/settings.rs"), /LinkSettings \{ visible: is_true\(raw\.get\("visible"\)\)/, "off unless exactly true");
});

test("only a click accepts: nothing in the link says yes to an offer by itself", () => {
  for (const [f, t] of linkProd) assert.doesNotMatch(t, /respond\(true\)/, f);
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/handle\.respond\(accept\)/g) ?? []).length, 1, "one place, in respond_offer, with the user's answer");
  assert.match(svc, /fn respond_offer\(&mut self, accept: bool, shown: Option<ShownView>\)/);
  assert.match(prod("src/link_cmd.rs"), /pub fn link_respond_offer\(link: State<'_, LinkHandle>, accept: bool, shown: Option<ShownView>\) \{\s*link\.0\.respond_offer\(accept, shown\);/);
});

test("a received file is never opened, run or followed: no process is started and nothing is opened from the link", () => {
  for (const [f, t] of [...linkProd, ["link_cmd.rs", prod("src/link_cmd.rs")]]) {
    assert.doesNotMatch(t, /Command::new|ShellExecute|open_url|opener|xdg-open|start_process/, f);
  }
  const cmd = prod("src/link_cmd.rs");
  assert.ok((cmd.match(/platform::reveal_file|platform::reveal_folder/g) ?? []).length === 2, "show in folder is the only thing done with a file");
  const files = prod("src/link/files.rs");
  assert.match(files, /create_new\(true\)/, "a received file is created exclusively");
  assert.match(files, /O_NOFOLLOW/);
  assert.match(files, /ZoneId=3/, "Windows: the mark of the web, zone 3");
  assert.match(files, /Zone\.Identifier/);
});

test("no secret on disk, no name in a log: the credential store is the keystore's alone, the log holds fixed sentences", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/keyring::/), ["keystore.rs"]);
  assert.deepEqual(where(/std::fs::(write|File::create)|fs::write\(/), ["files.rs", "settings.rs"], "the files the link writes: the mark of a received file (files.rs) and link.json, which holds the switch and the name");
  assert.match(prod("src/link/settings.rs"), /json!\(\{"visible": s\.visible, "deviceName": s\.device_name\}\)/, "and it holds the switch and the name, nothing else");
  assert.deepEqual(where(/println!|eprintln!|dbg!|log::line/), []);
  const cmd = prod("src/link_cmd.rs");
  assert.match(cmd, /fn log\(&self, line: &'static str\) \{\s*log::line\(line\);/);
  assert.equal((cmd.match(/log::line\(/g) ?? []).length, 1);
  const svc = read("src/link/service.rs");
  const lines = [...svc.matchAll(/self\.log\("([^"]+)"\)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(lines)].sort(), ["a pairing ended", "a transfer ended", "a transfer started", "listening", "stopped listening"]);
});

test("this computer's name is read in one place, for the default device name only", () => {
  const where = (re) => linkProd.filter(([, t]) => re.test(t)).map(([f]) => f);
  assert.deepEqual(where(/COMPUTERNAME|kernel\/hostname|\/etc\/hostname|gethostname/), ["settings.rs"]);
  assert.doesNotMatch(prod("src/link_cmd.rs").replace(/crate::link::settings::host_name\(\)/, ""), /COMPUTERNAME|hostname/);
  assert.doesNotMatch(prod("src/link/mdns.rs"), /host_name\(\)|COMPUTERNAME/, "the advert's host name is made from the device id");
  assert.match(prod("src/link/mdns.rs"), /format!\("notchmeow-\{\}\.local\.", id\.get\(\.\.8\)\.unwrap_or\(id\)\)/);
});

test("a debug build keeps its keys under a service name of its own", () => {
  assert.match(prod("src/link/keystore.rs"), /pub const SERVICE: &str = if cfg!\(debug_assertions\) \{ "io\.github\.aikusan\.notchmeow\.debug" \} else \{ "io\.github\.aikusan\.notchmeow" \};/);
});

test("the state the page sees is serialized by one type, and the commands take ids", () => {
  const cmd = prod("src/link_cmd.rs");
  assert.match(cmd, /crate::shelf_store\(\)\.resolve\(&ids\)/);
  assert.doesNotMatch(cmd, /pub (async )?fn link_\w+\([^)]*(PathBuf|Path\b|path:)/, "no command takes a path from the page");
});

test("the listener is IPv4 only with the contract's 10 s handshake, and the service holds a connection from the moment it is accepted", () => {
  const svc = prod("src/link/service.rs");
  assert.match(svc, /bind: "0\.0\.0\.0:0"\.parse\(\)\.unwrap\(\),/);
  assert.match(svc, /handshake: Duration::from_secs\(HANDSHAKE_SECONDS\),/);
  assert.match(svc, /Listener::start\(self\.cfg\.bind, on_connection, self\.cfg\.handshake\)\.await/);
  assert.match(read("src/link/net.rs"), /pub const HANDSHAKE_SECONDS: u64 = 10;/);
  assert.match(svc, /let _ = tx\.send\(Cmd::Track \{ conn, transport: transport\.clone\(\), gen \}\);\s*tokio::spawn/, "tracked when accepted, before its first record is read");
  assert.match(svc, /for \(_, t\) in self\.active\.drain\(\) \{\s*t\.abort\(\);\s*\}/, "stop_listening cuts every connection the service holds");
});

test("Devices on screen is a state: the pairing gate hears a transition, never a repeat, and the Settings window's hide says closed", () => {
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/pair_gate\.devices_appeared\(\)/g) ?? []).length, 1);
  assert.equal((svc.match(/pair_gate\.devices_disappeared\(\)/g) ?? []).length, 1);
  assert.match(svc, /if open == self\.devices_open \{[^}]*\{[^}]*\}[^}]*return;\s*\}\s*self\.devices_open = open;\s*if open \{\s*self\.pair_gate\.devices_appeared\(\);/, "the early return for a repeat comes before the gate is told");
  assert.match(prod("src/link_cmd.rs"), /pub fn settings_hidden\(app: &AppHandle\) \{[^}]*\{\s*link\.0\.set_devices_open\(false\);/);
});

test("the advert is made in one place and a name a card would refuse is not announced; the search is asked for again each time the machines are looked at", () => {
  const svc = prod("src/link/service.rs");
  assert.equal((svc.match(/discovery\.advertise\(/g) ?? []).length, 1);
  assert.match(svc, /fn announce\(&self, id: &str, name: &str, port: u16\) -> Result<\(\), String> \{\s*if !advertisable\(name\) \{\s*return Err\(ADVERT_PROBLEM\.into\(\)\);\s*\}\s*self\.deps\.discovery\.advertise\(id, name, port\)/);
  assert.match(svc, /fn advertisable\(name: &str\) -> bool \{\s*device_name\(name\.as_bytes\(\)\)\.is_ok\(\)/);
  assert.equal((svc.match(/self\.start_browser\(\);\s*\/\/ the page says it again/g) ?? []).length, 1, "Devices says open again: look again");
  assert.match(svc, /Cmd::ShelfOpen\(open\) => \{\s*if open == self\.shelf_open \{\s*if open \{\s*self\.start_browser\(\);/, "and so does the shelf");
});

test("the page is told what a conversation did only through a fixed label: no {:?} in the service, one text for a transfer that stopped", () => {
  const svc = prod("src/link/service.rs");
  assert.doesNotMatch(svc, /\{[a-z_0-9.]*:#?\?\}/, "no value of the service is ever printed with {:?}");
  assert.match(svc, /fixed_label!\(CardView, RowView, Snapshot, ShownView, Card\);/);
  assert.equal((svc.match(/"Transfer stopped"/g) ?? []).length, 1, "a disk that cannot be written and a drive that cannot hold the mark of the web end the same way");
  assert.match(svc, /TransferOutcome::Aborted\(_\) => Some\(Card::Result \{ title: "Transfer stopped"\.into\(\)/);
});

test("no value of the link is ever printed with {:?} in any production file of the link or in link_cmd.rs", () => {
  for (const [f, t] of [...linkProd, ["link_cmd.rs", prod("src/link_cmd.rs")]]) assert.doesNotMatch(t, /\{[a-z_0-9.]*:#?\?\}/, f);
});

test("every hook of a conversation carries the generation or the ticket it was made under, so a late event of a stopped one acts on nothing", () => {
  const svc = prod("src/link/service.rs");
  const cmd = svc.slice(svc.indexOf("enum Cmd {"), svc.indexOf("/// The handle the app holds"));
  for (const line of [
    "Browsed(Vec<Found>, u64),",
    "Preamble { conn: u64, transport: Arc<TcpTransport>, slot: PendingSlot, gen: u64, pre: Preamble },",
    "Track { conn: u64, transport: Arc<TcpTransport>, gen: u64 },",
    "OutboundFailed(u64),",
    "PairCode { ticket: Ticket, code: String, name: String },",
    "PairEnded { outcome: PairOutcome, initiator: Option<Initiator>, responder: Option<Responder>, own_id: String, gen: u64, outbound: bool },",
    "IncomingRefused(u64),",
    "OfferArrived { offer: Offer, handle: ReceiveHandle, conn: u64, gen: u64 },",
    "ReceiveEnded { conn: u64, outcome: TransferOutcome, gen: u64, handle: ReceiveHandle, peer_id: String },",
    "SendStatus(String, u64),",
    "SendDone(u64),",
  ]) assert.ok(cmd.includes(line), line);
  assert.match(svc, /Progress \{ conn: u64, got: u64 \}/, "a tick counts only for the run whose ticket is current");
  assert.match(svc, /if r\.conn != conn \|\| !self\.gate\.is_receive\(r\.ticket\) \{/);
  assert.match(svc, /if !self\.gate\.is_pair\(ticket\) \{/);
});
