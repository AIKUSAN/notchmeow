import SwiftUI

/// The `.shelf` island view (sub-project G1): the card every island view has, with the shelf's content in it.
struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    /// Sub-project G2: the machines this Mac is paired with, and the line a send in progress shows.
    @ObservedObject private var link = LinkService.shared
    /// The browser for paired machines is counted once per appearance, so an extra onAppear cannot leave it running (as DevicesSettingsSection does).
    @State private var counted = false

    var body: some View {
        // The machines a file can be sent to: every row that is paired, online or not (a row that is only seen is not one).
        let paired = link.rows.filter { $0.state != .available }
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            ShelfContent(model: model, hooks: ShelfDragHooks(began: { AppState.shared.shelfDragging = true }, ended: { AppState.shared.shelfDragging = false }), buttons: buttons(paired: paired))
                .accessibilityIdentifier(ShelfStore.marker)
        }
        // The browser for paired machines runs only while the shelf is on screen (sub-project G2).
        .onAppear { opened() }
        .onDisappear { closed() }
    }

    /// What the bar's buttons do. The Cancel beside the status line is there only while a send to a machine runs (`cancelSend`).
    private func buttons(paired: [LinkDirectory.Row]) -> ShelfButtons {
        var b = ShelfButtons(ask: { ShelfActions.ask($0, model: model) }, show: { ShelfActions.showInFinder($0, model: model) },
                             send: { ShelfActions.send($0, model: model) }, airDrop: { ShelfActions.airDrop($0, model: model) },
                             showDevicesButton: link.settings.visible || !paired.isEmpty,
                             devices: paired.map { ShelfDeviceChoice(id: $0.id, name: $0.name, online: $0.state == .pairedOnline) },
                             sendToDevice: { link.send($0, to: $1, model: model) }, deviceLine: link.sendStatus,
                             devicesHelp: { NotificationCenter.default.post(name: .openFullSettings, object: "devices") })
        if link.sending { b.cancelSend = { link.cancelSending() } }
        return b
    }

    /// Each side runs once per appearance, so the browser's openers never drift.
    private func opened() { guard !counted else { return }; counted = true; link.beginBrowsing() }
    private func closed() { guard counted else { return }; counted = false; link.endBrowsing() }
}
