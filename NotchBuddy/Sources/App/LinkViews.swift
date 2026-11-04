import SwiftUI

// The link's views (sub-project G2), in the style the app already has: the island card (`CardBackground`, the 12.5 pt buttons, grey 11 pt notes) for the pairing, the Accept card and the progress, and
// the GroupBox rows Settings already uses for Settings → Devices. They take plain values and closures, so scripts/render-link.sh draws them without the app. Nothing here changes a view that ships.

/// The size of a file the way people say it ("2.4 MB"): 1000-based, as Finder does.
enum LinkText {
    static func size(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file) }
    /// "483 291": the six digits in two groups, to read out and compare.
    static func spaced(_ code: String) -> String { code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code }
    static func percent(_ done: UInt64, _ total: UInt64) -> Int { total == 0 ? 100 : Int(min(100, done * 100 / total)) }
}

/// What the `.link` card's buttons do. Each button says which card it was drawn on (`LinkCardRules.Shown`, from `LinkService.Card.shown`), so the service can do nothing for a click that was meant
/// for a card that has since been replaced.
struct LinkCardActions {
    var answerPair: (Bool, LinkCardRules.Shown?) -> Void = { _, _ in }
    var respondOffer: (Bool, LinkCardRules.Shown?) -> Void = { _, _ in }
    var cancel: (LinkCardRules.Shown?) -> Void = { _ in }
    var showInFinder: (URL) -> Void = { _ in }
    var dismiss: (LinkCardRules.Shown?) -> Void = { _ in }

    init() {}

    init(answerPair: @escaping (Bool, LinkCardRules.Shown?) -> Void, respondOffer: @escaping (Bool, LinkCardRules.Shown?) -> Void, cancel: @escaping (LinkCardRules.Shown?) -> Void,
         showInFinder: @escaping (URL) -> Void, dismiss: @escaping (LinkCardRules.Shown?) -> Void) {
        self.answerPair = answerPair; self.respondOffer = respondOffer; self.cancel = cancel; self.showInFinder = showInFinder; self.dismiss = dismiss
    }

    /// Closures that do not take the card: the service then acts on the card that is on the island (still behind its 700 ms quiet period after a change of kind).
    init(answerPair: @escaping (Bool) -> Void, respondOffer: @escaping (Bool) -> Void, cancel: @escaping () -> Void, showInFinder: @escaping (URL) -> Void, dismiss: @escaping () -> Void) {
        self.init(answerPair: { yes, _ in answerPair(yes) }, respondOffer: { accept, _ in respondOffer(accept) }, cancel: { _ in cancel() }, showInFinder: showInFinder, dismiss: { _ in dismiss() })
    }
}

/// The `.link` island view's content: the pairing card, the Accept card, the progress of a file that is coming in, and the end of any of them.
struct LinkCardView: View {
    let card: LinkService.Card?
    var actions = LinkCardActions()

    var body: some View {
        ZStack {
            switch card {
            case .pair(let code, let peer, let answered)?: pair(code: code, peer: peer, answered: answered)
            case .offer(let o)?: offer(o)
            case .receiving(let o, let got)?: receiving(o, got)
            case .result(let title, let detail, let file)?: result(title, detail, file)
            case nil: CardBackground(wash: nil)
            }
        }
    }

    private func pad<V: View>(_ v: V) -> some View {
        v.padding(.leading, 116).padding(.trailing, 16).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pair(code: String, peer: String, answered: Bool) -> some View {
        ZStack {
            CardBackground(wash: .indigo)
            pad(VStack(alignment: .leading, spacing: 5) {
                Text("Pair with \(peer)?").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 10) {
                    Text(LinkText.spaced(code)).font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: "#F5F6F8")).accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
                    Text("Check that \(peer) shows the same six digits.").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(2)
                }
                HStack(spacing: 8) {
                    SecondaryButton("No") { actions.answerPair(false, card?.shown) }.disabled(answered)
                    PrimaryButton(answered ? "Waiting for \(peer)" : "They match") { actions.answerPair(true, card?.shown) }.disabled(answered)
                }
            })
        }
    }

    private func offer(_ o: LinkOffer) -> some View {
        ZStack {
            CardBackground(wash: .cyan)
            pad(VStack(alignment: .leading, spacing: 5) {
                Text("\(o.peerName) wants to send you a file").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1).truncationMode(.tail)
                // The name is the sanitized one: the one that would be saved.
                CodeBlock(text: "\(o.name)  \(LinkText.size(o.size))").lineLimit(1).truncationMode(.middle)
                Text("Saved in Downloads/NotchMeow, never opened for you. Declined by itself after 2 minutes.").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(2)
                HStack(spacing: 8) {
                    SecondaryButton("Decline") { actions.respondOffer(false, card?.shown) }
                    PrimaryButton("Accept") { actions.respondOffer(true, card?.shown) }
                }
            })
        }
    }

    private func receiving(_ o: LinkOffer, _ got: UInt64) -> some View {
        ZStack {
            CardBackground(wash: .cyan)
            pad(VStack(alignment: .leading, spacing: 6) {
                Text("Receiving \(o.name) from \(o.peerName)").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1).truncationMode(.middle)
                // Drawn, not a ProgressView: an AppKit-backed control cannot be drawn into the render script's pictures.
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(Color(hex: "#22D3EE")).frame(width: g.size.width * CGFloat(LinkText.percent(got, o.size)) / 100)
                    }
                }.frame(height: 6)
                HStack(spacing: 8) {
                    Text("\(LinkText.size(got)) of \(LinkText.size(o.size)), \(LinkText.percent(got, o.size)) %").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).monospacedDigit()
                    Spacer(minLength: 4)
                    SecondaryButton("Cancel") { actions.cancel(card?.shown) }
                }
            })
        }
    }

    private func result(_ title: String, _ detail: String, _ file: URL?) -> some View {
        ZStack {
            CardBackground(wash: file != nil ? .green : .soft)
            pad(VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text(detail).font(.system(size: 11.5)).foregroundColor(Color(hex: "#B9BDC4")).lineLimit(2)
                HStack(spacing: 8) {
                    if let file { SecondaryButton("Show in Finder") { actions.showInFinder(file) } }
                    PrimaryButton("OK") { actions.dismiss(card?.shown) }
                }
            })
        }
    }
}

/// Settings → Devices, as plain values: the app fills it from `LinkService` (`DevicesSettingsSection`), the render script from a stand-in.
struct DevicesSettingsView: View {
    var visible: Bool
    var deviceName: String
    var listening: Bool
    var problem: String?
    var note: String?
    var rows: [LinkDirectory.Row]
    var setVisible: (Bool) -> Void = { _ in }
    var rename: (String) -> Bool = { _ in true }
    var pair: (String) -> Void = { _ in }
    var forget: (String) -> Void = { _ in }
    var openLocalNetworkSettings: () -> Void = {}
    var showReceivedFolder: () -> Void = {}

    @State private var draft: String = ""
    @State private var nameRefused = false
    @State private var forgetting: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("This Mac") {
                SwitchRow("Visible on this network", isOn: Binding(get: { visible }, set: { setVisible($0) }))
                HelpText("Other Macs and PCs running NotchMeow can see this one and offer to pair. Until you turn this on, nothing listens and nothing is announced. Only machines you have paired can ever send a file.")
                SettingRow("Name") {
                    TextField("Name shown to other machines", text: $draft, onCommit: { nameRefused = !rename(draft) })
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: SettingsLayout.fieldMax)
                }
                HelpText("Machines on this network see this name.")
                if nameRefused { orangeNote("That name cannot be shown on another machine's card: use 1 to 63 characters, no control or invisible characters, no space at either end.") }
                if visible {
                    if problem == nil { HelpText(listeningLine) } else { orangeNote(listeningLine) }
                }
            }
            SettingsCard("Machines") {
                if !visible && rows.isEmpty {
                    HelpText("Turn on Visible on this network to find machines and pair with them.")
                } else if rows.isEmpty {
                    HelpText("No machines found")
                    HelpText("Both machines need NotchMeow running, Visible on this network turned on, and to be on the same network. Some office and guest networks block this.")
                }
                ForEach(rows, id: \.id) { row in
                    machineRow(row)
                }
                if let note { orangeNote(note) }
                WrapRow {
                    Button("Local Network permission…", action: openLocalNetworkSettings)
                        .buttonStyle(.bordered).controlSize(.small)
                }
                HelpText("If the list stays empty, check that NotchMeow is allowed under Privacy & Security, Local Network.")
            }
            SettingsCard("Received files") {
                HelpText("Files you accept are saved in Downloads/NotchMeow. They are marked as downloaded from elsewhere and are never opened for you.")
                Button("Show in Finder", action: showReceivedFolder)
            }
        }
        .onAppear { draft = deviceName }
    }

    /// The line under the visible switch: what the link is doing, or why it is not.
    private var listeningLine: String { listening ? "Listening on your network." : (problem ?? "Starting…") }

    /// A warning line: the orange of a problem.
    private func orangeNote(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
    }

    /// A machine: its dot, its name (wrapping), and in one line its status chip and its buttons.
    private func machineRow(_ row: LinkDirectory.Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(row.state == .pairedOffline ? Color.secondary.opacity(0.4) : (row.state == .pairedOnline ? Color.green : Color.blue))
                .frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name).fixedSize(horizontal: false, vertical: true)
                WrapRow {
                    StatusChip(row.state == .pairedOnline ? "Paired" : row.state == .pairedOffline ? "Paired, not seen" : "Available")
                    if row.state == .available { Button("Pair") { pair(row.id) } }
                    else if forgetting == row.id { Button("Forget \(row.name)?") { forget(row.id); forgetting = nil }.foregroundColor(.red); Button("Keep") { forgetting = nil } }
                    else { Button("Forget") { forgetting = row.id } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Settings → Devices in the app: the view above, filled from `LinkService`. Browsing for machines runs only while this section is on screen.
struct DevicesSettingsSection: View {
    @ObservedObject private var link = LinkService.shared
    @State private var counted = false

    var body: some View {
        DevicesSettingsView(visible: link.settings.visible, deviceName: link.settings.deviceName, listening: link.listening, problem: link.problem, note: link.note, rows: link.rows,
                            setVisible: { link.setVisible($0) }, rename: { link.setDeviceName($0) }, pair: { link.pair(with: $0) }, forget: { link.forget($0) },
                            openLocalNetworkSettings: { if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") { NSWorkspace.shared.open(u) } },
                            showReceivedFolder: {
                                let folder = LinkFileSink.defaultFolder()
                                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            })
            .accessibilityIdentifier(LinkService.marker)
            .onAppear { opened() }
            .onDisappear { closed() }
            // Closing the Settings window does not always send `onDisappear` to a hosted view (and showing it again does not send `onAppear`), and the pairing gate counts openers without a time bound:
            // the window's own close ends the section, and the window becoming key again starts it.
            .background(WindowWatcher(onOpen: { opened() }, onClose: { closed() }))
    }

    /// Each side runs once per appearance, whichever of `onAppear`, the window becoming key, `onDisappear` and the window's close comes first, so the gate's counter and the browser's openers never drift.
    private func opened() { guard !counted else { return }; counted = true; link.beginBrowsing(); link.devicesOpened() }
    private func closed() { guard counted else { return }; counted = false; link.endBrowsing(); link.devicesClosed() }
}

/// Calls `onOpen` when the window this view sits in becomes the key window, and `onClose` when it closes. Both are meant to be idempotent. The observers are removed when the view leaves its window
/// and when it is released.
private struct WindowWatcher: NSViewRepresentable {
    let onOpen: () -> Void
    let onClose: () -> Void
    func makeNSView(context: Context) -> Watcher { Watcher(onOpen: onOpen, onClose: onClose) }
    func updateNSView(_ view: Watcher, context: Context) { view.onOpen = onOpen; view.onClose = onClose }

    final class Watcher: NSView {
        var onOpen: () -> Void
        var onClose: () -> Void
        // A lock-protected box, so `deinit` (which is not isolated) can remove the observers too.
        private let tokens = ObserverTokens()
        init(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) { self.onOpen = onOpen; self.onClose = onClose; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("not used") }
        deinit { tokens.removeAll() }

        override func viewDidMoveToWindow() {
            tokens.removeAll()
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.add(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen() }
            })
            tokens.add(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            })
        }
    }
}

/// The observer tokens of one window watcher. Lock-protected, so the removal can run from `deinit` and from the main actor alike.
private final class ObserverTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NSObjectProtocol] = []
    func add(_ token: NSObjectProtocol) { lock.withLock { items.append(token) } }
    func removeAll() {
        let old = lock.withLock { () -> [NSObjectProtocol] in let o = items; items = []; return o }
        old.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
