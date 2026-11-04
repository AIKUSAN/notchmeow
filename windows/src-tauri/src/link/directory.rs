// What Settings → Devices lists and what the shelf's "To a device" offers: the machines seen on the network and the machines paired, merged. Pure, so the order and the states are tested.
// The Mac's twin is `LinkDirectory` (LinkSettings.swift).

use std::collections::BTreeMap;

use super::frames::Advert;
use super::identity::Peer;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowState {
    /// Paired, and its advert is on the network now.
    PairedOnline,
    /// Paired, not seen.
    PairedOffline,
    /// Seen, not paired.
    Available,
}

impl RowState {
    pub fn as_str(self) -> &'static str {
        match self {
            RowState::PairedOnline => "pairedOnline",
            RowState::PairedOffline => "pairedOffline",
            RowState::Available => "available",
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct Row {
    pub id: String,
    pub name: String,
    pub state: RowState,
}

impl std::fmt::Debug for Row {
    /// A fixed label: the id and the name are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Row").finish_non_exhaustive()
    }
}

fn by_name(a: &Row, b: &Row) -> std::cmp::Ordering {
    a.name.to_lowercase().cmp(&b.name.to_lowercase()).then_with(|| a.name.cmp(&b.name)).then_with(|| a.id.cmp(&b.id))
}

/// Paired machines that are online first (a paired machine's name is the authenticated one it gave when it paired, not the advert's), then the paired that are not, then the machines only seen,
/// each group by name. An advert with this machine's own id is never listed (`parse_txt` refuses it already; this is the second line).
pub fn rows(adverts: &[Advert], peers: &BTreeMap<String, Peer>, own_id: &str) -> Vec<Row> {
    let seen: BTreeMap<&str, &Advert> = adverts.iter().filter(|a| a.id != own_id).map(|a| (a.id.as_str(), a)).collect();
    let mut online = vec![];
    let mut offline = vec![];
    for p in peers.values() {
        let state = if seen.contains_key(p.id.as_str()) { RowState::PairedOnline } else { RowState::PairedOffline };
        let row = Row { id: p.id.clone(), name: p.name.clone(), state };
        if state == RowState::PairedOnline { online.push(row) } else { offline.push(row) }
    }
    let mut others: Vec<Row> = seen.values().filter(|a| !peers.contains_key(&a.id)).map(|a| Row { id: a.id.clone(), name: a.name.clone(), state: RowState::Available }).collect();
    online.sort_by(by_name);
    offline.sort_by(by_name);
    others.sort_by(by_name);
    online.into_iter().chain(offline).chain(others).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ad(id: &str, name: &str) -> Advert {
        Advert { id: id.repeat(32), name: name.into() }
    }

    fn peer(id: &str, name: &str) -> (String, Peer) {
        (id.repeat(32), Peer { id: id.repeat(32), name: name.into(), key: "ab".repeat(32), at: 0 })
    }

    #[test]
    fn paired_online_then_paired_offline_then_the_others_each_by_name() {
        let peers: BTreeMap<String, Peer> = [peer("1", "Zed laptop"), peer("2", "Alpha PC"), peer("3", "Mid tower")].into_iter().collect();
        let adverts = [ad("1", "zed (advert name)"), ad("4", "Beta"), ad("5", "alpha two"), ad("3", "Mid")];
        let got: Vec<(String, RowState)> = rows(&adverts, &peers, &"f".repeat(32)).into_iter().map(|r| (r.name, r.state)).collect();
        assert_eq!(
            got,
            vec![
                ("Mid tower".into(), RowState::PairedOnline),
                ("Zed laptop".into(), RowState::PairedOnline),
                ("Alpha PC".into(), RowState::PairedOffline),
                ("alpha two".into(), RowState::Available),
                ("Beta".into(), RowState::Available),
            ],
            "a paired machine keeps the name it gave when it paired, not the advert's"
        );
    }

    #[test]
    fn this_machines_own_advert_is_never_listed() {
        let own = "e".repeat(32);
        let got = rows(&[ad("e", "Me"), ad("a", "Other")], &BTreeMap::new(), &own);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name, "Other");
    }

    #[test]
    fn equal_names_are_ordered_by_id_and_a_row_prints_no_id_or_name() {
        let got = rows(&[ad("b", "Same"), ad("a", "Same")], &BTreeMap::new(), &"f".repeat(32));
        assert_eq!(got.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["a".repeat(32), "b".repeat(32)]);
        let row = Row { id: "5e".repeat(16), name: "Sam's MacBook Pro".into(), state: RowState::PairedOnline };
        let text = format!("{row:?}");
        assert!(!text.contains("5e5e") && !text.contains("Sam's"), "{text}");
    }

    #[test]
    fn two_adverts_with_one_id_make_one_row() {
        let got = rows(&[ad("a", "First"), ad("a", "Second")], &BTreeMap::new(), &"f".repeat(32));
        assert_eq!(got.len(), 1);
    }
}
