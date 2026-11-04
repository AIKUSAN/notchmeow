// The link's secrets (sub-project G2): this machine's static private key, its device id, and one item for each machine it has paired. They live in the operating system's credential store
// (the Windows Credential Manager, or on Linux the Secret Service: GNOME Keyring, KWallet) and nowhere else: never in a file, a setting, a log or a fixture (docs/LINK-CONTRACT.md "Notes
// for ports"). The account names are frozen like the pill IDs:
//   `link.static-key`   {"k": private key, "p": public key}, 64 lower-case hex digits each
//   `link.device-id`    this machine's random device id, 32 lower-case hex digits, never all zero
//   `link.peers`        the ids of the paired machines, a JSON list (the credential stores cannot list their items, so this list is the index)
//   `link.peer.<id>`    {"n": name, "k": public key, "t": seconds} for each paired machine
// `Keystore` takes the store it reads and writes, so the tests run it on a memory store.
//
// A read that fails is an error and never a fresh secret: only an item that is **absent** may lead to a new key or device id, so a locked or missing credential store can never replace
// the key and lose every pairing, and only a store that holds no id, no key and no index makes an identity (the id and the key together): a mix is damaged, not new. **Without a Secret Service on Linux** (no GNOME Keyring or KWallet running) every read fails, the link says so in Settings → Devices and stays off; it
// does not fall back to a file. A debug build keeps all of it under a service name of its own, so a dev run can never touch the real pairings.

use std::collections::BTreeMap;
use std::sync::Mutex;

use serde_json::{json, Value};

use super::bytes::{self, hex, is_id_hex, is_key_hex, ID_LEN};
use super::frames::device_name;
use super::identity::Peer;
use super::noise;

/// The credential store's service name.
pub const SERVICE: &str = if cfg!(debug_assertions) { "io.github.aikusan.notchmeow.debug" } else { "io.github.aikusan.notchmeow" };

pub const ACCOUNT_KEY: &str = "link.static-key";
pub const ACCOUNT_ID: &str = "link.device-id";
pub const ACCOUNT_PEERS: &str = "link.peers";
const PEER_PREFIX: &str = "link.peer.";
/// The label a damaged or missing paired-machine item is reported under: never the id.
const PEER_LABEL: &str = "link.peer";

/// What a store says about one item: there, not there, or not readable. Only `Absent` may lead to a new secret being made.
#[derive(Clone, PartialEq, Eq)]
pub enum Lookup {
    Absent,
    Found(String),
    Failed,
}

impl std::fmt::Debug for Lookup {
    /// A found value is a secret: a Debug print shows only that it was found.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Lookup::Absent => f.write_str("Absent"),
            Lookup::Found(_) => f.write_str("Found(..)"),
            Lookup::Failed => f.write_str("Failed"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoreError;

pub trait SecretStore: Send + Sync {
    fn get(&self, account: &str) -> Lookup;
    /// Writes the item, replacing what is there. Never deletes first: a failed write leaves the old item.
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError>;
    /// Removes the item; an item that is not there is not an error.
    fn delete(&self, account: &str) -> Result<(), StoreError>;
}

/// A store in memory, for the tests: nothing here touches the credential store.
#[derive(Default)]
pub struct MemoryStore {
    items: Mutex<BTreeMap<String, String>>,
    pub fail_reads: std::sync::atomic::AtomicBool,
    pub fail_writes: std::sync::atomic::AtomicBool,
}

impl SecretStore for MemoryStore {
    fn get(&self, account: &str) -> Lookup {
        if self.fail_reads.load(std::sync::atomic::Ordering::SeqCst) {
            return Lookup::Failed;
        }
        self.items.lock().unwrap().get(account).map_or(Lookup::Absent, |v| Lookup::Found(v.clone()))
    }
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError> {
        if self.fail_writes.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(StoreError);
        }
        self.items.lock().unwrap().insert(account.to_string(), value.to_string());
        Ok(())
    }
    fn delete(&self, account: &str) -> Result<(), StoreError> {
        self.items.lock().unwrap().remove(account);
        Ok(())
    }
}

impl MemoryStore {
    pub fn accounts(&self) -> Vec<String> {
        self.items.lock().unwrap().keys().cloned().collect()
    }
}

/// The real credential store (the `keyring` crate: Windows Credential Manager, Linux Secret Service).
#[cfg(any(windows, target_os = "linux"))]
pub struct SystemStore {
    service: String,
}

#[cfg(any(windows, target_os = "linux"))]
impl SystemStore {
    pub fn new() -> SystemStore {
        SystemStore { service: SERVICE.to_string() }
    }
    /// A store under another service name (the opt-in real-store test uses one made for its run).
    pub fn with_service(service: &str) -> SystemStore {
        SystemStore { service: service.to_string() }
    }
}

#[cfg(any(windows, target_os = "linux"))]
impl Default for SystemStore {
    fn default() -> SystemStore {
        SystemStore::new()
    }
}

/// What a `keyring` error means for a read: no such item is `Absent`, anything else (no Secret Service, a locked store, a refused prompt, an item that will not decode) is `Failed`.
#[cfg(any(windows, target_os = "linux"))]
pub fn lookup_of(result: Result<String, keyring::Error>) -> Lookup {
    match result {
        Ok(v) => Lookup::Found(v),
        Err(keyring::Error::NoEntry) => Lookup::Absent,
        Err(_) => Lookup::Failed,
    }
}

#[cfg(any(windows, target_os = "linux"))]
impl SecretStore for SystemStore {
    fn get(&self, account: &str) -> Lookup {
        match keyring::Entry::new(&self.service, account) {
            Ok(e) => lookup_of(e.get_password()),
            Err(_) => Lookup::Failed,
        }
    }
    fn put(&self, account: &str, value: &str) -> Result<(), StoreError> {
        keyring::Entry::new(&self.service, account).and_then(|e| e.set_password(value)).map_err(|_| StoreError)
    }
    fn delete(&self, account: &str) -> Result<(), StoreError> {
        match keyring::Entry::new(&self.service, account).map(|e| e.delete_credential()) {
            Ok(Ok(())) | Ok(Err(keyring::Error::NoEntry)) => Ok(()),
            _ => Err(StoreError),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyError {
    /// The store could not be read (locked, no Secret Service, a refused prompt). Nothing is replaced.
    Unreadable,
    /// An item is there and is not what it should be. It is never replaced; the user is told.
    Corrupt(String),
    /// The store would not take a write.
    Write,
    /// A map that came back empty where machines were known: a locked store lists nothing, so the last good map is kept.
    Suspect,
    /// A pairing that must not be stored: the id is this machine's own, not an id, or paired under another key.
    Refused(&'static str),
}

impl std::fmt::Display for KeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            KeyError::Unreadable => f.write_str("the credential store could not be read"),
            KeyError::Corrupt(what) => write!(f, "an item of the credential store is damaged: {what}"),
            KeyError::Write => f.write_str("the credential store would not take a write"),
            KeyError::Suspect => f.write_str("the credential store listed nothing where machines were known"),
            KeyError::Refused(why) => write!(f, "refused: {why}"),
        }
    }
}

impl std::error::Error for KeyError {}

pub struct Keystore<S: SecretStore> {
    store: S,
    /// One writer at a time: the first use of a secret and a change to the paired machines are read-then-write. (One instance of the app runs; the single-instance plugin sees to that.)
    turn: Mutex<()>,
}

fn random<const N: usize>() -> Option<[u8; N]> {
    let mut b = [0u8; N];
    getrandom::getrandom(&mut b).ok()?;
    Some(b)
}

impl<S: SecretStore> Keystore<S> {
    pub fn new(store: S) -> Keystore<S> {
        Keystore { store, turn: Mutex::new(()) }
    }

    pub fn store(&self) -> &S {
        &self.store
    }

    /// This machine's device id. Made on first use (the item is absent), never when the read failed.
    pub fn device_id(&self) -> Result<String, KeyError> {
        let _turn = self.turn.lock().unwrap();
        match self.store.get(ACCOUNT_ID) {
            Lookup::Found(v) if is_id_hex(&v) && v != "0".repeat(2 * ID_LEN) => Ok(v),
            Lookup::Found(_) => Err(KeyError::Corrupt(ACCOUNT_ID.into())),
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => self.make_identity(ACCOUNT_ID).map(|(id, _)| id),
        }
    }

    /// Makes the device id and the static key together, and only when the store holds no part of an identity: a key or an index beside a missing id (or the reverse) is a damaged store, not a fresh
    /// install, and a new half would orphan every pairing. `missing` is the item the caller found absent; what is reported is that item. A half-made identity (the second write failed) is taken back.
    fn make_identity(&self, missing: &str) -> Result<(String, ([u8; 32], [u8; 32])), KeyError> {
        for account in [ACCOUNT_ID, ACCOUNT_KEY, ACCOUNT_PEERS] {
            if account == missing {
                continue;
            }
            match self.store.get(account) {
                Lookup::Absent => {}
                Lookup::Found(_) => return Err(KeyError::Corrupt(missing.into())),
                Lookup::Failed => return Err(KeyError::Unreadable),
            }
        }
        let id = hex(&random::<ID_LEN>().ok_or(KeyError::Write)?);
        if id == "0".repeat(2 * ID_LEN) {
            return Err(KeyError::Write);
        }
        let (k, p) = noise::generate_static().map_err(|_| KeyError::Write)?;
        self.store.put(ACCOUNT_ID, &id).map_err(|_| KeyError::Write)?;
        if self.store.put(ACCOUNT_KEY, &json!({"k": hex(&k), "p": hex(&p)}).to_string()).is_err() {
            let _ = self.store.delete(ACCOUNT_ID);
            return Err(KeyError::Write);
        }
        Ok((id, (k, p)))
    }

    /// The static key pair (private, public). Made on first use, never when the read failed; an item whose public half is not the private half's is damaged.
    pub fn static_key(&self) -> Result<([u8; 32], [u8; 32]), KeyError> {
        let _turn = self.turn.lock().unwrap();
        match self.store.get(ACCOUNT_KEY) {
            Lookup::Found(v) => {
                let corrupt = || KeyError::Corrupt(ACCOUNT_KEY.into());
                let j: Value = serde_json::from_str(&v).map_err(|_| corrupt())?;
                let (k, p) = (bytes::key32(j["k"].as_str().unwrap_or("")).ok_or_else(corrupt)?, bytes::key32(j["p"].as_str().unwrap_or("")).ok_or_else(corrupt)?);
                if noise::public_of(&k).map_err(|_| corrupt())? != p {
                    return Err(corrupt());
                }
                Ok((k, p))
            }
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => self.make_identity(ACCOUNT_KEY).map(|(_, key)| key),
        }
    }

    fn index(&self) -> Result<Vec<String>, KeyError> {
        match self.store.get(ACCOUNT_PEERS) {
            Lookup::Absent => Ok(vec![]),
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Found(v) => {
                let list: Vec<String> = serde_json::from_str(&v).map_err(|_| KeyError::Corrupt(ACCOUNT_PEERS.into()))?;
                if list.iter().any(|i| !is_id_hex(i)) {
                    return Err(KeyError::Corrupt(ACCOUNT_PEERS.into()));
                }
                Ok(list)
            }
        }
    }

    fn peer(&self, id: &str) -> Result<Peer, KeyError> {
        let account = format!("{PEER_PREFIX}{id}");
        let corrupt = || KeyError::Corrupt(PEER_LABEL.into());
        match self.store.get(&account) {
            Lookup::Failed => Err(KeyError::Unreadable),
            Lookup::Absent => Err(corrupt()),
            Lookup::Found(v) => {
                let j: Value = serde_json::from_str(&v).map_err(|_| corrupt())?;
                let name = device_name(j["n"].as_str().ok_or_else(corrupt)?.as_bytes()).map_err(|_| corrupt())?;
                let key = j["k"].as_str().filter(|k| is_key_hex(k)).ok_or_else(corrupt)?.to_string();
                Ok(Peer { id: id.to_string(), name, key, at: j["t"].as_i64().unwrap_or(0) })
            }
        }
    }

    /// The paired machines, by id. A machine with an item that will not read is an error for the whole map (the caller keeps its last good one); `expecting_some` says the caller knew
    /// machines before, and a map that comes back empty then is `Suspect` (a locked store lists nothing).
    pub fn paired_machines(&self, expecting_some: bool) -> Result<BTreeMap<String, Peer>, KeyError> {
        let _turn = self.turn.lock().unwrap();
        self.read_all(expecting_some)
    }

    fn read_all(&self, expecting_some: bool) -> Result<BTreeMap<String, Peer>, KeyError> {
        let ids = self.index()?;
        let mut map = BTreeMap::new();
        for id in ids {
            map.insert(id.clone(), self.peer(&id)?);
        }
        if expecting_some && map.is_empty() {
            return Err(KeyError::Suspect);
        }
        Ok(map)
    }

    /// Stores a machine that both users said "They match" to. The paired map is read again here, at the moment of storing (two pairings can overlap for up to two minutes): an id that is this
    /// machine's own, or that is paired under another key, is refused; the same id under the same key updates its name.
    pub fn add(&self, peer: &Peer, own_id: &str) -> Result<(), KeyError> {
        let _turn = self.turn.lock().unwrap();
        if !is_id_hex(&peer.id) || peer.id == "0".repeat(2 * ID_LEN) {
            return Err(KeyError::Refused("device-id"));
        }
        if peer.id == own_id {
            return Err(KeyError::Refused("own-id"));
        }
        if !is_key_hex(&peer.key) || device_name(peer.name.as_bytes()).is_err() {
            return Err(KeyError::Refused("peer"));
        }
        let mut ids = self.index()?;
        let listed = ids.contains(&peer.id);
        if listed && self.peer(&peer.id)?.key != peer.key {
            return Err(KeyError::Refused("id-key-mismatch"));
        }
        // The item first, then the index: a crash between the two leaves an item nobody lists, never a listed machine without its key.
        self.store.put(&format!("{PEER_PREFIX}{}", peer.id), &json!({"n": peer.name, "k": peer.key, "t": peer.at}).to_string()).map_err(|_| KeyError::Write)?;
        if listed {
            return Ok(());
        }
        ids.push(peer.id.clone());
        self.store.put(ACCOUNT_PEERS, &serde_json::to_string(&ids).unwrap()).map_err(|_| KeyError::Write)
    }

    /// Forgets a machine: out of the index first (so it is no longer trusted), then its item goes.
    pub fn forget(&self, id: &str) -> Result<(), KeyError> {
        let _turn = self.turn.lock().unwrap();
        if !is_id_hex(id) {
            return Err(KeyError::Refused("device-id"));
        }
        let item = format!("{PEER_PREFIX}{id}");
        let mut ids = self.index()?;
        // The index is written only when the id is listed: with nothing listed (an absent index) it is not written.
        if ids.iter().any(|i| i == id) {
            ids.retain(|i| i != id);
            self.store.put(ACCOUNT_PEERS, &serde_json::to_string(&ids).unwrap()).map_err(|_| KeyError::Write)?;
        }
        self.store.delete(&item).map_err(|_| KeyError::Write)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    fn ks() -> Keystore<MemoryStore> {
        Keystore::new(MemoryStore::default())
    }

    fn peer(tag: u8, key: u8) -> Peer {
        Peer { id: hex(&[tag; 16]), name: format!("Machine {tag}"), key: hex(&[key; 32]), at: 1_700_000_000 }
    }

    #[test]
    fn the_service_name_of_a_debug_build_is_its_own() {
        assert_eq!(SERVICE, if cfg!(debug_assertions) { "io.github.aikusan.notchmeow.debug" } else { "io.github.aikusan.notchmeow" });
    }

    #[test]
    fn the_device_id_is_made_once_and_kept() {
        let k = ks();
        let id = k.device_id().unwrap();
        assert!(is_id_hex(&id) && id != "0".repeat(32));
        assert_eq!(k.device_id().unwrap(), id);
    }

    #[test]
    fn the_static_key_is_made_once_and_its_public_half_is_checked() {
        let k = ks();
        let (a, pa) = k.static_key().unwrap();
        let (b, pb) = k.static_key().unwrap();
        assert_eq!((a, pa), (b, pb));
        assert_eq!(noise::public_of(&a).unwrap(), pa);
        k.store().put(ACCOUNT_KEY, &json!({"k": hex(&a), "p": hex(&[1u8; 32])}).to_string()).unwrap();
        assert_eq!(k.static_key().unwrap_err(), KeyError::Corrupt(ACCOUNT_KEY.into()), "a key whose public half does not match is damaged, not replaced");
        assert!(matches!(k.store().get(ACCOUNT_KEY), Lookup::Found(v) if v.contains(&hex(&[1u8; 32]))), "and it is still there");
    }

    #[test]
    fn a_failed_read_never_makes_a_fresh_key_or_id() {
        let k = ks();
        let (_, pub1) = k.static_key().unwrap();
        let id = k.device_id().unwrap();
        k.store().fail_reads.store(true, Ordering::SeqCst);
        assert_eq!(k.static_key().unwrap_err(), KeyError::Unreadable);
        assert_eq!(k.device_id().unwrap_err(), KeyError::Unreadable);
        k.store().fail_reads.store(false, Ordering::SeqCst);
        assert_eq!(k.static_key().unwrap().1, pub1, "the key is the one that was there");
        assert_eq!(k.device_id().unwrap(), id);
        assert!(k.paired_machines(false).is_ok());
    }

    const ID_A: &str = "abababababababababababababababab";

    fn a_key() -> String {
        let (k, p) = noise::generate_static().unwrap();
        json!({"k": hex(&k), "p": hex(&p)}).to_string()
    }

    #[test]
    fn only_a_store_with_no_part_of_an_identity_makes_one_and_it_makes_both_halves() {
        // A fresh install: either call first, both halves exist afterwards and nothing is Corrupt.
        for key_first in [false, true] {
            let k = ks();
            let (id, key) = if key_first {
                let key = k.static_key().unwrap();
                (k.device_id().unwrap(), key)
            } else {
                let id = k.device_id().unwrap();
                (id, k.static_key().unwrap())
            };
            assert!(is_id_hex(&id));
            assert_eq!(k.static_key().unwrap(), key);
            assert_eq!(k.device_id().unwrap(), id);
            let mut accounts = k.store().accounts();
            accounts.sort();
            assert_eq!(accounts, vec![ACCOUNT_ID.to_string(), ACCOUNT_KEY.to_string()]);
        }
    }

    #[test]
    fn a_key_is_not_made_beside_an_id_or_an_index_that_is_there() {
        for (account, value) in [(ACCOUNT_ID, ID_A.to_string()), (ACCOUNT_PEERS, format!("[\"{ID_A}\"]")), (ACCOUNT_PEERS, "[]".to_string())] {
            let k = ks();
            k.store().put(account, &value).unwrap();
            assert_eq!(k.static_key().unwrap_err(), KeyError::Corrupt(ACCOUNT_KEY.into()), "{account}");
            assert!(!k.store().accounts().iter().any(|a| a == ACCOUNT_KEY), "no key was made beside {account}");
        }
    }

    #[test]
    fn an_id_is_not_made_beside_a_key_or_an_index_that_is_there() {
        for (account, value) in [(ACCOUNT_KEY, a_key()), (ACCOUNT_PEERS, format!("[\"{ID_A}\"]")), (ACCOUNT_PEERS, "[]".to_string())] {
            let k = ks();
            k.store().put(account, &value).unwrap();
            assert_eq!(k.device_id().unwrap_err(), KeyError::Corrupt(ACCOUNT_ID.into()), "{account}");
            assert!(!k.store().accounts().iter().any(|a| a == ACCOUNT_ID), "no id was made beside {account}");
        }
    }

    #[test]
    fn a_half_made_identity_is_not_left_behind_when_the_store_will_not_take_the_second_item() {
        // The store takes the first write and refuses the next one.
        struct OneWrite(MemoryStore, std::sync::atomic::AtomicUsize);
        impl SecretStore for OneWrite {
            fn get(&self, a: &str) -> Lookup {
                self.0.get(a)
            }
            fn put(&self, a: &str, v: &str) -> Result<(), StoreError> {
                if self.1.fetch_add(1, Ordering::SeqCst) >= 1 {
                    return Err(StoreError);
                }
                self.0.put(a, v)
            }
            fn delete(&self, a: &str) -> Result<(), StoreError> {
                self.0.delete(a)
            }
        }
        let k = Keystore::new(OneWrite(MemoryStore::default(), Default::default()));
        assert_eq!(k.device_id().unwrap_err(), KeyError::Write);
        assert!(k.store().0.accounts().is_empty(), "the first half was taken back: the next try starts from nothing, and no mix is left to be called damaged");
    }

    #[test]
    fn a_damaged_device_id_is_reported_and_not_replaced() {
        let k = ks();
        k.store().put(ACCOUNT_ID, "not an id").unwrap();
        assert_eq!(k.device_id().unwrap_err(), KeyError::Corrupt(ACCOUNT_ID.into()));
        k.store().put(ACCOUNT_ID, &"0".repeat(32)).unwrap();
        assert_eq!(k.device_id().unwrap_err(), KeyError::Corrupt(ACCOUNT_ID.into()));
    }

    #[test]
    fn a_pairing_is_stored_listed_and_forgotten() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.add(&peer(2, 2), &own).unwrap();
        let map = k.paired_machines(false).unwrap();
        assert_eq!(map.len(), 2);
        assert_eq!(map[&hex(&[1u8; 16])], peer(1, 1));
        k.forget(&hex(&[1u8; 16])).unwrap();
        assert_eq!(k.paired_machines(true).unwrap().keys().collect::<Vec<_>>(), vec![&hex(&[2u8; 16])]);
        assert!(!k.store().accounts().contains(&format!("link.peer.{}", hex(&[1u8; 16]))), "its item is gone");
    }

    #[test]
    fn the_same_machine_again_updates_its_name_and_another_key_is_refused() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        let mut renamed = peer(1, 1);
        renamed.name = "New name".into();
        k.add(&renamed, &own).unwrap();
        assert_eq!(k.paired_machines(false).unwrap()[&hex(&[1u8; 16])].name, "New name");
        assert_eq!(k.add(&peer(1, 7), &own).unwrap_err(), KeyError::Refused("id-key-mismatch"), "the user removes the device first to re-pair");
        assert_eq!(k.paired_machines(false).unwrap()[&hex(&[1u8; 16])].key, hex(&[1u8; 32]));
    }

    #[test]
    fn this_machines_own_id_and_bad_peers_are_refused() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        assert_eq!(k.add(&peer(9, 1), &own).unwrap_err(), KeyError::Refused("own-id"));
        let mut zero = peer(1, 1);
        zero.id = "0".repeat(32);
        assert_eq!(k.add(&zero, &own).unwrap_err(), KeyError::Refused("device-id"));
        let mut bad_key = peer(1, 1);
        bad_key.key = "AB".repeat(32);
        assert_eq!(k.add(&bad_key, &own).unwrap_err(), KeyError::Refused("peer"));
        let mut bad_name = peer(1, 1);
        bad_name.name = " padded ".into();
        assert_eq!(k.add(&bad_name, &own).unwrap_err(), KeyError::Refused("peer"));
        assert!(k.paired_machines(false).unwrap().is_empty());
    }

    #[test]
    fn an_empty_list_where_machines_were_known_is_suspect_and_a_damaged_item_fails_the_read() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.store().put(ACCOUNT_PEERS, "[]").unwrap();
        assert_eq!(k.paired_machines(true).unwrap_err(), KeyError::Suspect);
        assert!(k.paired_machines(false).unwrap().is_empty());
        k.store().put(ACCOUNT_PEERS, &format!("[\"{}\"]", hex(&[1u8; 16]))).unwrap();
        k.store().put(&format!("link.peer.{}", hex(&[1u8; 16])), "{\"n\":\"x\"}").unwrap();
        assert!(matches!(k.paired_machines(false).unwrap_err(), KeyError::Corrupt(_)));
        // An index that names a machine whose item is gone is damaged too.
        k.store().delete(&format!("link.peer.{}", hex(&[1u8; 16]))).unwrap();
        assert!(matches!(k.paired_machines(false).unwrap_err(), KeyError::Corrupt(_)));
    }

    #[test]
    fn a_failed_write_keeps_what_was_there_and_says_so() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        k.add(&peer(1, 1), &own).unwrap();
        k.store().fail_writes.store(true, Ordering::SeqCst);
        assert_eq!(k.add(&peer(2, 2), &own).unwrap_err(), KeyError::Write);
        assert_eq!(k.forget(&hex(&[1u8; 16])).unwrap_err(), KeyError::Write);
        k.store().fail_writes.store(false, Ordering::SeqCst);
        assert_eq!(k.paired_machines(false).unwrap().len(), 1);
    }

    #[test]
    fn no_secret_appears_in_an_error_or_a_debug_print() {
        let k = ks();
        let (private, _) = k.static_key().unwrap();
        for e in [KeyError::Unreadable, KeyError::Corrupt("link.static-key".into()), KeyError::Write, KeyError::Suspect, KeyError::Refused("own-id")] {
            assert!(!format!("{e} {e:?}").contains(&hex(&private)));
        }
    }

    #[test]
    fn a_damaged_or_missing_peer_item_names_no_part_of_the_id() {
        let k = ks();
        let own = hex(&[9u8; 16]);
        let id = hex(&[0x5e; 16]);
        k.add(&peer(0x5e, 1), &own).unwrap();
        let item = format!("link.peer.{id}");
        k.store().put(&item, "{\"n\":\"x\"}").unwrap();
        let damaged = k.paired_machines(false).unwrap_err();
        assert_eq!(damaged, KeyError::Corrupt("link.peer".into()));
        k.store().delete(&item).unwrap();
        let missing = k.paired_machines(false).unwrap_err();
        assert_eq!(missing, KeyError::Corrupt("link.peer".into()));
        k.store().fail_reads.store(true, Ordering::SeqCst);
        let unreadable = k.paired_machines(false).unwrap_err();
        assert_eq!(unreadable, KeyError::Unreadable);
        for e in [damaged, missing, unreadable] {
            let text = format!("{e} {e:?}");
            assert!(!text.contains(&id) && !text.contains(&id[..8]), "{text}");
        }
    }

    #[test]
    fn forget_writes_no_index_when_nothing_is_listed_and_refuses_a_bad_id() {
        let k = ks();
        k.forget(&hex(&[1u8; 16])).unwrap();
        assert!(!k.store().accounts().iter().any(|a| a == ACCOUNT_PEERS), "no [] is written");
        assert_eq!(k.forget("not hex").unwrap_err(), KeyError::Refused("device-id"));
    }

    #[test]
    fn a_found_lookup_prints_no_value() {
        let k = ks();
        let (private, _) = k.static_key().unwrap();
        let found = k.store().get(ACCOUNT_KEY);
        assert!(matches!(found, Lookup::Found(_)));
        assert!(!format!("{found:?}").contains(&hex(&private)));
    }
}
