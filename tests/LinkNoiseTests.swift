import CryptoKit
import Foundation

// The Noise layer of the link (docs/LINK-CONTRACT.md): every vector of tests/fixtures/link/noise-vectors.json replayed against LinkNoise.swift, every damaged-message case, and the size limits.
// Run it through scripts/test-link-noise.sh.

func linkHex(_ s: String) -> Data {
    var d = Data(), i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}
func linkHx(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

@main
enum LinkNoiseTests {
    enum Outcome: Equatable { case ok([String], String), fail(Int, LinkNoiseError) }

    /// `noise_run` of reference.py: plays a vector's whole conversation, both sides, in this process.
    /// A mutation damages what is delivered, never what is sent.
    static func run(_ v: [String: Any], _ m: [String: Any] = [:]) -> Outcome {
        let kind = m["kind"] as? String
        let pattern = LinkPattern(rawValue: String((v["protocol_name"] as! String).split(separator: "_")[1]))!
        let isk = try! LinkNoise.privateKey(raw: linkHex(v["init_static"] as! String)), rsk = try! LinkNoise.privateKey(raw: linkHex(v["resp_static"] as! String))
        let kk = pattern == .kk
        let iPro = linkHex((kind == "prologue" ? m["prologue"] : v["init_prologue"]) as! String)
        var i = try! LinkHandshake(pattern: pattern, initiator: true, prologue: iPro, s: isk, rs: kk ? LinkNoise.publicKey(of: rsk) : nil,
                                   e: try! LinkNoise.privateKey(raw: linkHex(v["init_ephemeral"] as! String)))
        let respRemote = kind == "static" ? linkHex(m["respRemoteStatic"] as! String) : LinkNoise.publicKey(of: isk)
        var r = try! LinkHandshake(pattern: pattern, initiator: false, prologue: linkHex(v["resp_prologue"] as! String), s: rsk, rs: kk ? respRemote : nil,
                                   e: try! LinkNoise.privateKey(raw: linkHex(v["resp_ephemeral"] as! String)))
        let nhs = pattern.messages.count
        var sent: [String] = [], hash = Data()
        var iSend = LinkCipherState(), iRecv = LinkCipherState(), rSend = LinkCipherState(), rRecv = LinkCipherState()
        for (n, msg) in (v["messages"] as! [[String: String]]).enumerated() {
            let payload = linkHex(msg["payload"]!)
            let toResp = n % 2 == 0
            let c: Data
            do {
                if n < nhs { c = toResp ? try i.write(payload) : try r.write(payload) }
                else { c = toResp ? try iSend.encrypt(ad: Data(), payload) : try rSend.encrypt(ad: Data(), payload) }
            } catch let e as LinkNoiseError { return .fail(n, e) } catch { fatalError() }
            sent.append(linkHx(c))
            var delivered = [c]
            if (m["message"] as? Int) == n {
                switch kind {
                case "flip": let o = m["offset"] as! Int; var d = c; d[o] ^= 1; delivered = [d]
                case "truncate": delivered = [c.prefix(c.count - (m["by"] as! Int))]
                case "low-order": delivered = [Data(count: 32) + c.dropFirst(32)]
                case "replay": delivered = [c, c]
                default: break
                }
            }
            if kind == "skip", (m["message"] as! Int) - 2 == n { delivered = [] }
            for d in delivered {
                let got: Data
                do {
                    if n < nhs { got = toResp ? try r.read(d) : try i.read(d) }
                    else { got = toResp ? try rRecv.decrypt(ad: Data(), d) : try iRecv.decrypt(ad: Data(), d) }
                } catch let e as LinkNoiseError { return .fail(n, e) } catch { fatalError() }
                if d == c && got != payload { return .fail(n, .decrypt) }
            }
            if n == nhs - 1 {
                let a = try! i.finish(), b = try! r.finish()
                if a.hash != b.hash { return .fail(n, .decrypt) }
                (iSend, iRecv, rSend, rRecv, hash) = (a.send, a.receive, b.send, b.receive, a.hash)
            }
        }
        return .ok(sent, linkHx(hash))
    }

    @MainActor static func main() {
        let f = CT.fixture("noise-vectors.json", dir: "link")
        CT.section("noise-vectors.json: every message and the handshake hash")
        let vectors = f["vectors"] as! [[String: Any]]
        CT.check("four vectors", vectors.map { $0["id"] as! String }.sorted(), ["kk-empty", "kk-link", "xx-empty", "xx-link"])
        CT.check("the prologue is notchmeow-link/1", linkHx(LinkNoise.prologue), f["prologue"] as! String)
        var byId: [String: [String: Any]] = [:]
        for v in vectors {
            byId[v["id"] as! String] = v
            let want = Outcome.ok((v["messages"] as! [[String: String]]).map { $0["ciphertext"]! }, v["handshake_hash"] as! String)
            CT.check("\(v["id"] as! String): every ciphertext and the hash are the vector's", run(v), want)
        }

        CT.section("rejectCases: a damaged conversation stops where the contract says")
        for c in f["rejectCases"] as! [[String: Any]] {
            var m = c; for k in ["name", "vector", "failsAt", "because"] { m[k] = nil }
            let got = run(byId[c["vector"] as! String]!, m)
            if case .fail(let at, let why) = got {
                CT.check(c["name"] as! String, at, c["failsAt"] as! Int)
                if c["because"] as? String == "low-order point" { CT.check("   refused as a low-order point", why, .lowOrderPoint) }
            } else { CT.checkTrue("\(c["name"] as! String): the conversation went through", false) }
        }

        CT.section("sizes, the counter, the key checks")
        let a0 = try! LinkNoise.privateKey(raw: Data(repeating: 1, count: 32)), b0 = try! LinkNoise.privateKey(raw: Data(repeating: 2, count: 32))
        var a = try! LinkHandshake(pattern: .kk, initiator: true, s: a0, rs: LinkNoise.publicKey(of: b0))
        var b = try! LinkHandshake(pattern: .kk, initiator: false, s: b0, rs: LinkNoise.publicKey(of: a0))
        _ = try! b.read(try! a.write()); _ = try! a.read(try! b.write())
        var aSend = try! a.finish().send, bRecv = try! b.finish().receive
        let big = try! aSend.encrypt(ad: Data(), Data(count: 65535 - 16))
        CT.check("a transport message of 65535 bytes opens", [big.count, (try! bRecv.decrypt(ad: Data(), big)).count], [65535, 65519])
        var tooBig = false
        do { _ = try aSend.encrypt(ad: Data(), Data(count: 65535 - 16 + 1)) } catch { tooBig = (error as? LinkNoiseError) == .tooLong }
        CT.check("one byte more is refused when sent, and the counter does not move", [tooBig, aSend.n == 1], [true, true])
        let next = try! aSend.encrypt(ad: Data(), Data("next".utf8))
        var hurt = next; hurt[0] ^= 1
        var refused = false
        do { _ = try bRecv.decrypt(ad: Data(), hurt) } catch { refused = (error as? LinkNoiseError) == .decrypt }
        CT.check("a damaged message is refused and the counter does not move", [refused, bRecv.n == 1], [true, true])
        CT.check("so the genuine next one still opens", String(decoding: try! bRecv.decrypt(ad: Data(), next), as: UTF8.self), "next")
        var shortBox = false
        do { _ = try bRecv.decrypt(ad: Data(), Data(count: 5)) } catch { shortBox = (error as? LinkNoiseError) == .decrypt }
        CT.checkTrue("a box shorter than a tag is refused, not trapped", shortBox)
        var kkNeeds = false
        do { _ = try LinkHandshake(pattern: .kk, initiator: true, s: a0) } catch { kkNeeds = (error as? LinkNoiseError) == .needsRemoteStatic }
        CT.checkTrue("KK without the peer's key is refused", kkNeeds)
        var badKey = false
        do { _ = try LinkNoise.dh(a0, Data(count: 31)) } catch { badKey = (error as? LinkNoiseError) == .invalidKey }
        CT.checkTrue("a public key of 31 bytes is refused", badKey)
        var xx = try! LinkHandshake(pattern: .xx, initiator: true, prologue: Data(), s: a0)
        var oversize = false
        do { _ = try xx.write(Data(count: 65535 - 31)) } catch { oversize = (error as? LinkNoiseError) == .tooLong }
        CT.checkTrue("a handshake message of 65536 bytes is refused", oversize)
        var notTurn = false
        do { _ = try xx.read(Data(count: 40)) } catch { notTurn = (error as? LinkNoiseError) == .notMyTurn }
        CT.checkTrue("reading on the writer's turn is refused", notTurn)

        CT.section("random sessions, both patterns")
        var ok = true
        for n in 0..<24 {
            let pattern: LinkPattern = n % 2 == 0 ? .xx : .kk
            let isk = Curve25519.KeyAgreement.PrivateKey(), rsk = Curve25519.KeyAgreement.PrivateKey()
            let pro = Data((0..<Int.random(in: 0..<20)).map { _ in UInt8.random(in: 0...255) })
            var i = try! LinkHandshake(pattern: pattern, initiator: true, prologue: pro, s: isk, rs: pattern == .kk ? LinkNoise.publicKey(of: rsk) : nil)
            var r = try! LinkHandshake(pattern: pattern, initiator: false, prologue: pro, s: rsk, rs: pattern == .kk ? LinkNoise.publicKey(of: isk) : nil)
            while !i.isDone {
                let p = Data((0..<Int.random(in: 0..<80)).map { _ in UInt8.random(in: 0...255) })
                if i.isMyTurn { ok = ok && (try! r.read(try! i.write(p))) == p } else { ok = ok && (try! i.read(try! r.write(p))) == p }
            }
            let fi = try! i.finish(), fr = try! r.finish()
            ok = ok && fi.hash == fr.hash && i.remoteStatic == LinkNoise.publicKey(of: rsk) && r.remoteStatic == LinkNoise.publicKey(of: isk)
            var send = fi.send, recv = fr.receive
            let p = Data((0..<Int.random(in: 1..<300)).map { _ in UInt8.random(in: 0...255) })
            let c = try! send.encrypt(ad: Data(), p)
            var d = c; d[Int.random(in: 0..<c.count)] ^= UInt8(1 << Int.random(in: 0..<8))
            ok = ok && (try? recv.decrypt(ad: Data(), d)) == nil && (try? recv.decrypt(ad: Data(), c)) == p
        }
        CT.checkTrue("24 sessions: the hashes agree, each side learns the other's key, any damaged bit is refused", ok)
        CT.finish()
    }
}
