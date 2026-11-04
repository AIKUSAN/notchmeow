import Foundation

// The rules that keep one link flow's card from being replaced by another's, and that ignore a click for a card that is gone or has only just appeared (LinkCardRules, sub-project G2). Pure:
// no clock (`now` is a number the test chooses), no network, no Keychain. Run it through scripts/test-link-service.sh.

@main
enum LinkServiceTests {
    typealias R = LinkCardRules
    static let pair = R.Shown(kind: .pair, key: "483291|Desk PC")
    static let otherPair = R.Shown(kind: .pair, key: "111111|Old laptop")
    static let offer = R.Shown(kind: .offer, key: "t1")
    static let otherOffer = R.Shown(kind: .offer, key: "t2")
    static let receiving = R.Shown(kind: .receiving, key: "t1")
    static let result = R.Shown(kind: .result, key: "Paired|This Mac and Desk PC")
    static let otherResult = R.Shown(kind: .result, key: "Received|a.pdf")

    @MainActor static func main() {
        CT.section("nothing on the island")
        var r = R()
        CT.check("is not interactive, and a click acts on nothing", [r.interactive, r.accepts(nil, now: 100_000), r.accepts(pair, now: 100_000)], [false, false, false])

        CT.section("a card in front of the user is never replaced by another flow's")
        r = R()
        CT.checkTrue("a pairing takes the free island", r.show(pair, owner: "pair:A", now: 1_000))
        CT.checkTrue("and is interactive", r.interactive)
        CT.check("an incoming pairing with another code is refused, and nothing changes", [r.show(otherPair, owner: "pair:B", now: 2_000), r.shown == pair, r.owner == "pair:A"], [false, true, true])
        CT.check("an incoming offer is refused too", [r.show(offer, owner: "transfer:t1", now: 2_000), r.shown == pair], [false, true])
        CT.check("a result of another flow does not replace it", [r.show(result, owner: "pair:B", now: 2_000), r.shown == pair], [false, true])

        r = R()
        _ = r.show(offer, owner: "transfer:t1", now: 1_000)
        CT.check("a waiting offer is not replaced by a pairing code or by another offer", [r.show(pair, owner: "pair:A", now: 5_000), r.show(otherOffer, owner: "transfer:t2", now: 5_000), r.shown == offer], [false, false, true])
        CT.checkTrue("the same transfer may go on to receiving", r.show(receiving, owner: "transfer:t1", now: 9_000) && r.shown == receiving)
        CT.check("and that is a change of kind", r.changedAt, 9_000)

        CT.section("a card that is over gives way")
        r = R()
        _ = r.show(result, owner: "pair:A", now: 1_000)
        CT.check("a result is not interactive", r.interactive, false)
        CT.checkTrue("an offer replaces another flow's result", r.show(offer, owner: "transfer:t1", now: 2_000) && r.shown == offer)
        CT.check("as a change of kind", r.changedAt, 2_000)

        CT.section("a flow that ends changes the card only if it is still its own")
        r = R()
        _ = r.show(pair, owner: "pair:A", now: 1_000)
        CT.check("another flow's end clears nothing", [r.end(owner: "transfer:t1"), r.shown == pair], [false, true])
        CT.check("its own end clears the card", [r.end(owner: "pair:A"), r.shown == nil, r.interactive], [true, true, false])
        r = R()
        _ = r.show(offer, owner: "transfer:t1", now: 1_000)
        CT.check("another flow's result does not overwrite the offer, its own result does", [r.show(result, owner: "pair:A", now: 2_000), r.show(result, owner: "transfer:t1", now: 3_000), r.shown == result], [false, true, true])

        CT.section("a click")
        r = R()
        _ = r.show(pair, owner: "pair:A", now: 10_000)
        CT.check("in the first 700 ms after the card appeared does nothing; at 700 ms it acts", [r.accepts(pair, now: 10_000), r.accepts(pair, now: 10_699), r.accepts(pair, now: 10_700)], [false, false, true])
        CT.check("for a card that is not the one on screen does nothing, at any time", [r.accepts(otherPair, now: 50_000), r.accepts(offer, now: 50_000), r.accepts(result, now: 50_000)], [false, false, false])
        CT.check("without an identity acts on the current card once it has settled", [r.accepts(nil, now: 10_100), r.accepts(nil, now: 20_000)], [false, true])
        _ = r.show(R.Shown(kind: .pair, key: pair.key), owner: "pair:A", now: 30_000)
        CT.check("the user's own answer (same card, same kind) does not start a new quiet period", r.accepts(pair, now: 30_000), true)
        _ = r.show(result, owner: "pair:A", now: 40_000)
        CT.check("a change of kind does: the Accept click that lands on the next card's button is ignored", [r.accepts(result, now: 40_300), r.accepts(result, now: 40_700), r.accepts(pair, now: 41_000)], [false, true, false])

        CT.section("an offer is identified by the machine and the transfer id together")
        let fromDesk = R.offerKey(peerId: "d1", transferId: "t1"), fromLaptop = R.offerKey(peerId: "l1", transferId: "t1")
        CT.check("the same transfer id from another machine is another key", [fromDesk == fromLaptop, fromDesk == R.offerKey(peerId: "d1", transferId: "t1")], [false, true])
        let deskOffer = R.Shown(kind: .offer, key: fromDesk), laptopOffer = R.Shown(kind: .offer, key: fromLaptop)
        r = R()
        _ = r.show(deskOffer, owner: "transfer:\(fromDesk)", now: 1_000)
        CT.check("a click meant for the other machine's offer does nothing; another machine's offer with the same id is refused", [r.accepts(laptopOffer, now: 9_000), r.show(laptopOffer, owner: "transfer:\(fromLaptop)", now: 9_000), r.accepts(deskOffer, now: 9_000)], [false, false, true])

        CT.section("a late event from a stopped conversation is stale")
        var g = LinkRunGate()
        let first = g.beginReceive()
        CT.check("the current run's ticket is the receive run's, and not the pairing's", [g.isReceive(first), g.isPair(first)], [true, false])
        g.stop()
        CT.check("after Visible is turned off it is stale, and the stop is counted", [g.isReceive(first), g.generation == 1], [false, true])
        let second = g.beginReceive()
        CT.check("a new run is another ticket; the old run's late progress or offer still does not count", [second == first, g.isReceive(second), g.isReceive(first)], [false, true, false])
        g.endReceive()
        CT.check("ending the run makes its ticket stale at once, before any new run begins", g.isReceive(second), false)
        let third = g.beginReceive()
        CT.check("a run that ended in the same generation is stale as soon as another begins", [g.isReceive(second), g.isReceive(third)], [false, true])
        let pairTicket = g.beginPair()
        g.stop()
        CT.check("a pairing ticket is stale after stop", g.isPair(pairTicket), false)
        let again = g.beginPair()
        g.endPair()
        CT.check("and after its own end", g.isPair(again), false)

        CT.section("a second offer is declined as busy before any card can be taken from it")
        let b = LinkBusy()
        CT.check("an offer claims the free island once; a second one from the same machine is refused", [b.claim("d1"), b.claim("d1")], [true, false])
        CT.check("a pairing code cannot take the card while an offer is claimed and has none yet", b.reserveCard(), false)
        CT.check("the run holds the claim until it is released; after that the accept is not for it", [b.holds("d1"), { b.release("d1"); return b.holds("d1") }()], [true, false])
        CT.check("a pairing code reserves the card; an offer that arrives next is refused at the claim", [b.reserveCard(), b.claim("d2")], [true, false])
        b.setCardLocked(false)
        CT.check("with the card free again an offer is claimed", b.claim("d2"), true)
        let one = LinkBusy()
        CT.check("the island has one card: while one machine's offer is claimed, another machine's is refused too", [one.claim("d1"), one.claim("d2"), { one.release("d1"); return one.claim("d2") }()], [true, false, true])

        CT.section("how many connections may be established")
        let caps = LinkConnectionCaps()
        let c = (0..<9).map { _ in UUID() }
        CT.check("a machine gets 2 connections, not 3", [caps.admit(c[0], peer: "d1"), caps.admit(c[1], peer: "d1"), caps.admit(c[2], peer: "d1")], [true, true, false])
        CT.check("asking again for a connection that is counted changes nothing", [caps.admit(c[0], peer: "d1"), caps.count == 2], [true, true])
        CT.check("three more machines fill the 8 in all", [caps.admit(c[3], peer: "d2"), caps.admit(c[4], peer: "d2"), caps.admit(c[5], peer: "d3"), caps.admit(c[6], peer: "d3"), caps.admit(c[7], peer: "d4"), caps.admit(c[8], peer: "d4"), caps.count == 8], [true, true, true, true, true, true, true])
        CT.check("the ninth is refused, whoever it is", caps.admit(UUID(), peer: "d5"), false)
        caps.release(c[0])
        CT.check("a connection that ended frees its place, for its machine and for the total", [caps.admit(UUID(), peer: "d1"), caps.admit(UUID(), peer: "d5")], [true, false])

        CT.section("the paired map is read again, but not in a loop")
        var limit = LinkReadLimit()
        CT.check("a first read is due", limit.due(now: 1_000), true)
        limit.read(now: 1_000)
        CT.check("another is not due before 5 s have passed: 4 999 ms no, 5 000 ms yes", [limit.due(now: 1_000), limit.due(now: 5_999), limit.due(now: 6_000)], [false, false, true])
        limit.read(now: 6_000)
        CT.check("a read at any time (Devices opened) moves the window", [limit.due(now: 10_999), limit.due(now: 11_000)], [false, true])

        CT.section("the clock")
        let t0 = LinkClock.nowMs()
        Thread.sleep(forTimeInterval: 0.25)
        let dt = LinkClock.nowMs() - t0
        CT.checkTrue("it moves in whole milliseconds, with the wall (250 ms of sleep is read as 250 to 2000, was \(dt): a busy CI runner oversleeps)", dt >= 250 && dt < 2000)
        CT.finish()
    }
}
