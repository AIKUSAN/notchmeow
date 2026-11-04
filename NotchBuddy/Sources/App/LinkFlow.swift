import Foundation

// What each side of a transfer does with each frame (sub-project G2, docs/LINK-CONTRACT.md "What each side does with each frame"): `receiverStep` and `senderStep` are pure. A state, one event
// (a frame, a click, a timeout), and the answer: the next state, the frames to send, what to tell the user, and why the connection must close. A port of `receiver_step` and `sender_step` of
// tests/fixtures/link/reference.py, replayed against flow-cases.json by scripts/test-link-flow.sh. Foundation only (the sanitizer is LinkName).
//
// Only a click (`accept`) starts a transfer. One transfer at a time on a connection; the app declines an offer as busy (reason 2) itself when another transfer is already running on this Mac
// (one for the whole Mac, whichever machine it comes from: the island has one card), since the reference models one connection only.

enum LinkFlow {
    typealias Frame = LinkWire.Frame

    enum Notify: String, Equatable, Sendable {
        case offer, expired, withdrawn, cancelled, complete, declined
    }

    /// Why the connection must close. After an abort the state is idle and nothing is saved as complete.
    enum Abort: String, Equatable, Sendable {
        case unexpected, id, order, overflow, short
    }

    enum Decline {
        static let user: UInt8 = 0, timeout: UInt8 = 1, busy: UInt8 = 2, tooLarge: UInt8 = 3, badOffer: UInt8 = 4
    }

    struct Out<State: Equatable & Sendable>: Equatable, Sendable {
        var state: State
        var send: [Frame] = []
        var notify: Notify? = nil
        var abort: Abort? = nil
    }

    enum UserAction: Equatable, Sendable { case accept, decline, cancel }

    // MARK: The receiver

    /// `name` is the sanitized name, the one that is shown and saved.
    enum ReceiverState: Equatable, Sendable {
        case idle
        case offered(id: Data, size: UInt64, name: String)
        case receiving(id: Data, size: UInt64, got: UInt64)
    }

    enum Event: Equatable, Sendable {
        case frame(Frame)
        case user(UserAction)
        case timeout
    }

    static func receiverStep(_ state: ReceiverState, _ event: Event) -> Out<ReceiverState> {
        switch event {
        case .user(let u):
            switch (state, u) {
            case (.offered(let id, let size, _), .accept): return Out(state: .receiving(id: id, size: size, got: 0), send: [.accept(id: id)])
            case (.offered(let id, _, _), .decline): return Out(state: .idle, send: [.decline(id: id, reason: Decline.user)])
            case (.receiving(let id, _, _), .cancel), (.receiving(let id, _, _), .decline): return Out(state: .idle, send: [.cancel(id: id)], notify: .cancelled)
            default: return Out(state: state)
            }
        case .timeout:
            if case .offered(let id, _, _) = state { return Out(state: .idle, send: [.decline(id: id, reason: Decline.timeout)], notify: .expired) }
            return Out(state: state)
        case .frame(let f):
            switch f {
            case .pairYes, .pairNo:
                return Out(state: .idle, abort: .unexpected)            // a pairing answer has no place in a transfer
            case .offer(let id, let size, let rawName, _):
                guard case .idle = state else { return Out(state: state, send: [.decline(id: id, reason: Decline.busy)]) }
                if size > LinkWire.sizeMax { return Out(state: .idle, send: [.decline(id: id, reason: Decline.tooLarge)]) }
                guard case .ok(let name) = LinkName.sanitize(rawName) else { return Out(state: .idle, send: [.decline(id: id, reason: Decline.badOffer)]) }
                return Out(state: .offered(id: id, size: size, name: name), notify: .offer)
            case .cancel(let id):
                switch state {
                case .offered(let own, _, _) where own == id: return Out(state: .idle, notify: .withdrawn)
                case .receiving(let own, _, _) where own == id: return Out(state: .idle, notify: .cancelled)
                default: return Out(state: state)                       // a cancel for a transfer we do not know is harmless
                }
            case .chunk(let id, let offset, let data):
                guard case .receiving(let own, let size, let got) = state else { return Out(state: .idle, abort: .unexpected) }
                guard id == own else { return Out(state: .idle, abort: .id) }
                guard offset == got else { return Out(state: .idle, abort: .order) }          // a replayed chunk or a skipped one
                guard got + UInt64(data.count) <= size else { return Out(state: .idle, abort: .overflow) }
                return Out(state: .receiving(id: own, size: size, got: got + UInt64(data.count)))
            case .done(let id):
                guard case .receiving(let own, let size, let got) = state else { return Out(state: .idle, abort: .unexpected) }
                guard id == own else { return Out(state: .idle, abort: .id) }
                guard got == size else { return Out(state: .idle, abort: .short) }
                return Out(state: .idle, notify: .complete)
            case .accept, .decline:
                return Out(state: .idle, abort: .unexpected)
            }
        }
    }

    // MARK: The sender

    enum SenderState: Equatable, Sendable {
        case idle
        case offered(id: Data)
        case sending(id: Data)
    }

    enum SenderEvent: Equatable, Sendable {
        case frame(Frame)
        case userCancel
        case userOther
    }

    static func senderStep(_ state: SenderState, _ event: SenderEvent) -> Out<SenderState> {
        let current: Data?
        switch state { case .idle: current = nil; case .offered(let id), .sending(let id): current = id }
        switch event {
        case .userCancel:
            if let id = current { return Out(state: .idle, send: [.cancel(id: id)], notify: .cancelled) }
            return Out(state: state)
        case .userOther:
            return Out(state: state)
        case .frame(let f):
            var fid: Data?
            switch f {
            case .accept(let id), .done(let id), .cancel(let id), .decline(let id, _), .chunk(let id, _, _), .offer(let id, _, _, _): fid = id
            case .pairYes, .pairNo: fid = nil
            }
            if case .cancel = f, current == nil { return Out(state: state) }   // a cancel with no transfer running is ignored
            switch f {
            case .offer, .chunk, .done, .pairYes, .pairNo: return Out(state: .idle, abort: .unexpected)
            default: break
            }
            guard let current else { return Out(state: .idle, abort: .unexpected) }
            guard fid == current else { return Out(state: .idle, abort: .id) }
            switch (state, f) {
            case (.offered, .accept): return Out(state: .sending(id: current))
            case (.offered, .decline): return Out(state: .idle, notify: .declined)
            case (_, .cancel): return Out(state: .idle, notify: .cancelled)
            default: return Out(state: .idle, abort: .unexpected)
            }
        }
    }
}
