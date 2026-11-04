import Foundation

// The bytes of the link on the wire (sub-project G2, docs/LINK-CONTRACT.md "On the wire"): records, the preamble, the hello, the advert's TXT record and the frames. A port of
// `encode_record`, `split_records`, `encode_preamble`/`decode_preamble`, `encode_hello`/`decode_hello`, `parse_txt`, `encode_frame`/`decode_frame` of tests/fixtures/link/reference.py,
// replayed against frames.json by scripts/test-link-frames.sh. Foundation only. Every decoder is strict: a name is UTF-8 without surrogates or overlong forms (`String(validating:)`, never
// a decoder that repairs), `kind` is printable ASCII, nothing may be left over, and a bad input is an error with a cause, never a trap.

enum LinkFrameError: String, Error, Equatable, Sendable {
    case empty, truncated, trailing, reason, kind, utf8, length, version, mode, id
    case unknownType = "unknown-type"
    case chunkEmpty = "chunk-empty"
    case chunkLong = "chunk-long"
    case nameLength = "name-length"
    case nameChars = "name-chars"
    case deviceId = "device-id"
    case ownId = "own-id"
    case recordLength = "record-length"
    case recordEmpty = "record-empty"
    case notARecord = "not-a-record"
}

enum LinkWire {
    static let protocolVersion: UInt8 = 1
    static let idLen = 16
    static let noiseMax = 65535
    static let tag = 16
    static let chunkMax = noiseMax - tag - 1 - idLen - 8   // 65494: a chunk frame and the tag fill one Noise message exactly
    static let chunkSize = 32768                            // what a sender cuts a file into
    static let rawNameMax = 1020                            // bytes of a name on the wire: 255 code points of up to 4 bytes
    static let kindMax = 127
    static let deviceNameMax = 63
    static let sizeMax: UInt64 = 4 * 1024 * 1024 * 1024    // 4 GiB inclusive
    static let declineBadOffer: UInt8 = 4
    static let typePairYes: UInt8 = 0x21, typePairNo: UInt8 = 0x22

    // MARK: Records

    /// A record is a u16 big-endian length (1 to 65535) and that many bytes. Every Noise message, handshake or transport, travels in one.
    static func encodeRecord(_ payload: Data) throws -> Data {
        guard (1...noiseMax).contains(payload.count) else { throw LinkFrameError.recordLength }
        return Data(LinkBytes.beUInt16(UInt16(payload.count))) + payload
    }

    /// The whole records at the start of `buffer` and the bytes of a record that has not arrived completely. A length of 0 is an error and closes the connection.
    static func splitRecords(_ buffer: Data) throws -> (records: [Data], rest: Data) {
        let b = [UInt8](buffer)
        var out: [Data] = [], pos = 0
        while b.count - pos >= 2 {
            let n = Int(LinkBytes.readUInt16(b[pos..<pos + 2]))
            if n == 0 { throw LinkFrameError.recordEmpty }
            if b.count - pos - 2 < n { break }
            out.append(Data(b[pos + 2..<pos + 2 + n]))
            pos += 2 + n
        }
        return (out, Data(b[pos...]))
    }

    // MARK: Preamble

    enum Mode: UInt8, Sendable { case pair = 1, transfer = 2 }
    struct Preamble: Equatable, Sendable { let mode: Mode; let id: String }

    /// The first record of a connection, in the clear: version, mode and the sender's device id (16 zero bytes when pairing).
    static func encodePreamble(mode: Mode, deviceId: Data) -> Data { Data([protocolVersion, mode.rawValue]) + deviceId }

    static func decodePreamble(_ data: Data) throws -> Preamble {
        let b = [UInt8](data)
        guard b.count == 2 + idLen else { throw LinkFrameError.length }
        guard b[0] == protocolVersion else { throw LinkFrameError.version }
        guard let mode = Mode(rawValue: b[1]) else { throw LinkFrameError.mode }
        let zero = b[2...].allSatisfy { $0 == 0 }
        guard (mode == .pair) == zero else { throw LinkFrameError.deviceId }
        return Preamble(mode: mode, id: LinkBytes.hex(b[2...]))
    }

    // MARK: Device name, hello, advert

    /// A device name is shown on a card: 1 to 63 bytes of strict UTF-8, no control, format or separator character, no invisible character (the table of a file name), no space at either end.
    static func deviceName(_ raw: [UInt8]) throws -> String {
        guard (1...deviceNameMax).contains(raw.count) else { throw LinkFrameError.nameLength }
        guard let s = String(validating: raw, as: UTF8.self) else { throw LinkFrameError.utf8 }
        let sc = Array(s.unicodeScalars)
        // Python's strip() also removes the other white space, but every such character is a control, a separator or a Zs, and the first two are refused above.
        if sc.contains(where: { LinkName.isBadCategory($0) || LinkName.isInvisible($0) }) || LinkName.isSpace(sc[0]) || LinkName.isSpace(sc[sc.count - 1]) { throw LinkFrameError.nameChars }
        return s
    }

    struct Hello: Equatable, Sendable { let id: String; let nonce: String; let name: String }

    /// The payload of the second and third pairing messages: version, device id, a 32-byte nonce, name length and name. It is encrypted, so the name on the card is the authenticated one.
    static func encodeHello(deviceId: Data, nonce: Data, name: String) -> Data {
        let nb = Array(name.utf8)
        return Data([protocolVersion]) + deviceId + nonce + Data([UInt8(nb.count)]) + Data(nb)
    }

    static func decodeHello(_ data: Data) throws -> Hello {
        let b = [UInt8](data)
        guard b.count >= 2 + idLen + 32 else { throw LinkFrameError.truncated }
        guard b[0] == protocolVersion else { throw LinkFrameError.version }
        guard !b[1..<1 + idLen].allSatisfy({ $0 == 0 }) else { throw LinkFrameError.deviceId }
        let n = Int(b[1 + idLen + 32]), body = Array(b[(2 + idLen + 32)...])
        guard body.count >= n else { throw LinkFrameError.truncated }
        guard body.count == n else { throw LinkFrameError.trailing }
        return Hello(id: LinkBytes.hex(b[1..<1 + idLen]), nonce: LinkBytes.hex(b[1 + idLen..<1 + idLen + 32]), name: try deviceName(body))
    }

    struct Advert: Equatable, Sendable { let id: String; let name: String }

    /// An advert's TXT record (`_notchmeow._tcp`): anyone on the network can send one, so it is checked like a name on a card. `v` must be the text "1", `id` 32 lower-case hex digits that are not
    /// all zero. An advert with this machine's own id is refused (`own-id`); an own id that is not 32 lower-case hex digits, a null one included, refuses every advert (`device-id`, fail closed).
    /// It carries no key: a paired id under another key is decided at the hello.
    static func parseTxt(_ txt: [String: String], ownId: LinkOwnId = .absent) throws -> Advert {
        guard txt["v"] == String(protocolVersion) else { throw LinkFrameError.version }
        guard let id = txt["id"], LinkBytes.isIdHex(id), id != LinkBytes.zeroId else { throw LinkFrameError.deviceId }
        switch ownId {
        case .absent: break
        case .null: throw LinkFrameError.deviceId
        case .value(let own):
            guard LinkBytes.isIdHex(own) else { throw LinkFrameError.deviceId }
            if id == own { throw LinkFrameError.ownId }
        }
        guard let name = txt["name"] else { throw LinkFrameError.nameLength }
        return Advert(id: id, name: try deviceName(Array(name.utf8)))
    }

    // MARK: Frames

    enum Frame: Equatable, Sendable {
        case offer(id: Data, size: UInt64, name: String, kind: String)
        case accept(id: Data)
        case decline(id: Data, reason: UInt8)
        case chunk(id: Data, offset: UInt64, data: Data)
        case done(id: Data)
        case cancel(id: Data)
        case pairYes
        case pairNo
    }

    /// A frame is the plaintext of one Noise transport message: a type byte, the 16-byte transfer id, then the body (numbers big-endian). The two pairing answers are the type byte alone.
    static func encode(_ frame: Frame) throws -> Data {
        func header(_ type: UInt8, _ id: Data) throws -> [UInt8] {
            guard id.count == idLen else { throw LinkFrameError.id }
            return [type] + [UInt8](id)
        }
        switch frame {
        case .pairYes: return Data([typePairYes])
        case .pairNo: return Data([typePairNo])
        case .offer(let id, let size, let name, let kind):
            let nb = Array(name.utf8), kb = Array(kind.utf8)
            return Data(try header(1, id) + LinkBytes.beUInt64(size) + LinkBytes.beUInt16(UInt16(truncatingIfNeeded: nb.count)) + nb + [UInt8(truncatingIfNeeded: kb.count)] + kb)
        case .accept(let id): return Data(try header(2, id))
        case .decline(let id, let reason): return Data(try header(3, id) + [reason])
        case .chunk(let id, let offset, let data): return Data(try header(4, id) + LinkBytes.beUInt64(offset)) + data
        case .done(let id): return Data(try header(5, id))
        case .cancel(let id): return Data(try header(6, id))
        }
    }

    static func decode(_ data: Data) throws -> Frame {
        let b = [UInt8](data)
        guard let type = b.first else { throw LinkFrameError.empty }
        guard (1...6).contains(type) || type == typePairYes || type == typePairNo else { throw LinkFrameError.unknownType }
        let body = Array(b.dropFirst())
        if type == typePairYes || type == typePairNo {
            guard body.isEmpty else { throw LinkFrameError.trailing }
            return type == typePairYes ? .pairYes : .pairNo
        }
        guard body.count >= idLen else { throw LinkFrameError.truncated }
        let id = Data(body[..<idLen]), rest = Array(body[idLen...])
        switch type {
        case 2, 5, 6:
            guard rest.isEmpty else { throw LinkFrameError.trailing }
            return type == 2 ? .accept(id: id) : type == 5 ? .done(id: id) : .cancel(id: id)
        case 3:
            guard rest.count >= 1 else { throw LinkFrameError.truncated }
            guard rest.count == 1 else { throw LinkFrameError.trailing }
            guard rest[0] <= declineBadOffer else { throw LinkFrameError.reason }
            return .decline(id: id, reason: rest[0])
        case 4:
            guard rest.count >= 8 else { throw LinkFrameError.truncated }
            let payload = Array(rest[8...])
            guard !payload.isEmpty else { throw LinkFrameError.chunkEmpty }
            guard payload.count <= chunkMax else { throw LinkFrameError.chunkLong }
            return .chunk(id: id, offset: LinkBytes.readUInt64(rest[0..<8]), data: Data(payload))
        default:
            guard rest.count >= 10 else { throw LinkFrameError.truncated }
            let size = LinkBytes.readUInt64(rest[0..<8]), n = Int(LinkBytes.readUInt16(rest[8..<10]))
            guard (1...rawNameMax).contains(n) else { throw LinkFrameError.nameLength }
            guard rest.count >= 10 + n + 1 else { throw LinkFrameError.truncated }
            let nameBytes = Array(rest[10..<10 + n]), k = Int(rest[10 + n]), kindBytes = Array(rest[(11 + n)...])
            guard kindBytes.count >= k else { throw LinkFrameError.truncated }
            guard kindBytes.count == k else { throw LinkFrameError.trailing }
            guard k <= kindMax, kindBytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { throw LinkFrameError.kind }
            guard let name = String(validating: nameBytes, as: UTF8.self) else { throw LinkFrameError.utf8 }
            return .offer(id: id, size: size, name: name, kind: String(decoding: kindBytes, as: UTF8.self))
        }
    }

    /// The pieces a sender cuts a file of `size` bytes into: (offset, length) pairs of `chunkSize` bytes, the last one short. An empty file has none.
    static func planChunks(size: UInt64, chunkSize: Int = chunkSize) -> [(offset: UInt64, length: Int)] {
        guard size > 0, chunkSize > 0 else { return [] }
        var out: [(UInt64, Int)] = [], at: UInt64 = 0
        while at < size { let n = Int(min(UInt64(chunkSize), size - at)); out.append((at, n)); at += UInt64(n) }
        return out
    }
}
