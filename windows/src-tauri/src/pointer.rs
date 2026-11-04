// Mouse button edges for the outside click (island.rs). The poll reads "is any button down" every tick while the island is expanded; this turns two reads into a press or a
// release. Pure, so the Linux container tests it like the rest.

/// One change of the buttons' state between two reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edge {
    Press,
    Release,
}

#[derive(Debug, Default)]
pub struct ButtonEdges {
    down: bool,
}

impl ButtonEdges {
    /// One read: `Some(Press)` when a button has just gone down, `Some(Release)` when the last one has just come up, `None` when nothing changed.
    pub fn step(&mut self, down: bool) -> Option<Edge> {
        let edge = match (self.down, down) {
            (false, true) => Some(Edge::Press),
            (true, false) => Some(Edge::Release),
            _ => None,
        };
        self.down = down;
        edge
    }

    /// Adopts the current state without reporting an edge: the watch has just been switched on, and a button already held then was pressed before it (its release is not a click).
    pub fn sync(&mut self, down: bool) {
        self.down = down;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_press_and_a_release_are_each_reported_once() {
        let mut e = ButtonEdges::default();
        assert_eq!(e.step(false), None);
        assert_eq!(e.step(true), Some(Edge::Press));
        assert_eq!(e.step(true), None, "held: no new edge");
        assert_eq!(e.step(true), None);
        assert_eq!(e.step(false), Some(Edge::Release));
        assert_eq!(e.step(false), None);
    }

    #[test]
    fn a_button_already_down_when_the_watch_starts_is_not_a_press() {
        let mut e = ButtonEdges::default();
        e.sync(true);
        assert_eq!(e.step(true), None);
        assert_eq!(e.step(false), Some(Edge::Release), "its release still comes, and the page ignores a release it saw no press for");
    }

    #[test]
    fn two_quick_clicks_between_reads_are_one_edge_pair_per_read() {
        let mut e = ButtonEdges::default();
        let seen: Vec<_> = [true, false, true, false].iter().filter_map(|d| e.step(*d)).collect();
        assert_eq!(seen, vec![Edge::Press, Edge::Release, Edge::Press, Edge::Release]);
    }
}
