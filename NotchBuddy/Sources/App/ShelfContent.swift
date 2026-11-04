import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The shelf view's content (sub-project G1): a title row, one row of tiles and an action bar, in the island's style. It is drawn inside the card (ShelfView.swift), 90 pt in from the left so
// that the cat keeps its place. It knows only the model, so the render script can draw it.

enum ShelfIcons {
    @MainActor private static var cache: [String: NSImage] = [:]

    /// The type's icon: a folder, or the one for the file's extension. Asked of the system by type, so no access to the file is needed.
    @MainActor static func icon(for item: ShelfItem) -> NSImage {
        let ext = item.folder ? "/" : (item.name as NSString).pathExtension.lowercased()
        if let hit = cache[ext] { return hit }
        let type = item.folder ? UTType.folder : (UTType(filenameExtension: ext) ?? UTType.data)
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let selected: Bool
    let missing: Bool

    static let size = CGSize(width: 72, height: 56)

    /// The line under the name: what the tile shows, and what the tile's accessibility label says after the name.
    static func detail(_ item: ShelfItem, missing: Bool) -> String {
        missing ? "Missing" : (item.folder ? "Folder" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
    }
    private static let accent = Color(hex: "#A5B4FC")

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: ShelfIcons.icon(for: item))
                .resizable().interpolation(.high)
                .frame(width: 26, height: 26)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#D5D7DB"))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: Self.size.width - 8)
            Text(Self.detail(item, missing: missing))
                .font(.system(size: 9, weight: .regular))
                .foregroundColor(missing ? Color(hex: "#F5A524") : Color(hex: "#8E939C"))
                .lineLimit(1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Self.accent.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Self.accent.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1))
        .opacity(missing ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A machine the shelf's items can be sent to (sub-project G2).
struct ShelfDeviceChoice: Equatable {
    let id: String
    let name: String
    let online: Bool
}

/// What the buttons of the action bar do; the app fills it in (`ShelfView`).
struct ShelfButtons {
    var ask: @MainActor (ShelfItem) -> Void
    var show: @MainActor ([ShelfItem]) -> Void
    var send: @MainActor ([ShelfItem]) -> Void
    var airDrop: @MainActor ([ShelfItem]) -> Void
    /// Sub-project G2, all additive: "To a device" shows when the link is on or a machine is paired. `devices` lists the paired machines (online first), `sendToDevice` starts the send for the
    /// chosen one, `deviceLine` is the status of a send in progress, and `devicesHelp` opens Settings → Devices.
    var showDevicesButton = false
    var devices: [ShelfDeviceChoice] = []
    var sendToDevice: @MainActor ([ShelfItem], String) -> Void = { _, _ in }
    var deviceLine: String? = nil
    var devicesHelp: @MainActor () -> Void = {}
    /// Set while a send to a device runs: the status line then has a Cancel beside it. Nil otherwise (nothing is drawn).
    var cancelSend: (@MainActor () -> Void)? = nil
    @MainActor static let none = ShelfButtons(ask: { _ in }, show: { _ in }, send: { _ in }, airDrop: { _ in })
}

/// One button of the action bar: a small icon and a word, dimmed when it does not work on the selection.
struct ShelfBarButton: View {
    let title: String
    let icon: String
    var tint = Color(hex: "#B9BDC4")
    var enabled = true
    var hint: String?
    /// What VoiceOver says for an icon-alone button (empty title); the title otherwise.
    var label = ""
    /// The widest the word may be; a longer name is cut short with "…" (the machines' chips, which can carry any name).
    var maxWidth: CGFloat?
    let action: () -> Void

    var body: some View {
        // An empty title is an icon alone (the "To a device" button: the bar has no room for another word).
        Button(action: action) { if title.isEmpty { Image(systemName: icon).font(.system(size: 11)) } else { Label(title, systemImage: icon).font(.system(size: 11)) } }
            .buttonStyle(.plain)
            .foregroundColor(tint)
            // Only a button with a width limit is cut to one line; the others keep their look.
            .lineLimit(maxWidth == nil ? nil : 1)
            .frame(maxWidth: maxWidth)
            .opacity(enabled ? 1 : 0.35)
            .disabled(!enabled)
            .help(hint ?? title)
            .accessibilityLabel(label.isEmpty ? title : label)
    }
}

struct ShelfContent: View {
    @ObservedObject var model: ShelfModel
    /// True when the view is drawn into a picture (the render script): `ImageRenderer` draws a `ScrollView` blank and a hosted AppKit view as a placeholder, so the row does not scroll and
    /// the tiles take no mouse.
    var picture = false
    /// What the app does when a drag out begins and ends.
    var hooks = ShelfDragHooks.none
    /// What the buttons do. The picture has none: they are drawn and do nothing.
    var buttons = ShelfButtons.none
    /// "To a device" is open: the bar lists the machines instead of the buttons.
    @State private var choosingDevice: Bool

    /// `startsChoosing` opens the machines at once: the render script's picture of them. The app starts with the buttons.
    init(model: ShelfModel, picture: Bool = false, hooks: ShelfDragHooks = .none, buttons: ShelfButtons = .none, startsChoosing: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        self.picture = picture
        self.hooks = hooks
        self.buttons = buttons
        _choosingDevice = State(initialValue: startsChoosing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Shelf").font(.system(size: 13, weight: .semibold))
                if model.count > 0 {
                    Text("\(model.count) of \(ShelfRules.max)").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                Spacer(minLength: 8)
                if let note = model.note {
                    Text(note).font(.system(size: 11)).foregroundColor(Color(hex: "#F5A524")).lineLimit(1).truncationMode(.tail)
                } else if let line = buttons.deviceLine {
                    Text(line).font(.system(size: 11)).foregroundColor(Color(hex: "#B9BDC4")).lineLimit(1).truncationMode(.tail)
                }
                if let cancel = buttons.cancelSend {
                    // The status line gives way to it (it truncates), so Cancel stays in view.
                    Button("Cancel") { cancel() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Color(hex: "#B9BDC4")).fixedSize().layoutPriority(1)
                        .help("Stop sending")
                        .accessibilityLabel("Cancel sending")
                }
                if model.count > 0 {
                    Button("Clear all") { model.clear() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .frame(height: 16)

            if model.items.isEmpty {
                VStack(spacing: 3) {
                    Text("Nothing on the shelf").font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#B9BDC4"))
                    Text("Drop files on the right half of the notch to keep them for later.").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .frame(maxWidth: .infinity, minHeight: ShelfTile.size.height)
            } else {
                tileRow.frame(height: ShelfTile.size.height)
            }

            actionBar.frame(height: 20)
        }
        .padding(.leading, 90)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
        // Nothing selected, or no device button to open the machines from: the chips close, so a later selection shows the buttons, not the chips.
        .onChange(of: model.selection.isEmpty || !buttons.showDevicesButton) { _, hidden in if hidden { choosingDevice = false } }
    }

    @ViewBuilder private var tileRow: some View {
        let row = HStack(spacing: 6) {
            ForEach(model.items, id: \.id) { item in
                let tile = ShelfTile(item: item, selected: model.selection.contains(item.id), missing: model.missing.contains(item.id))
                if picture {
                    tile
                } else {
                    // The AppKit overlay is the accessibility element (ShelfTileNSView); the tile under it is not read a second time.
                    tile.accessibilityHidden(true).overlay { ShelfTileMouse(model: model, item: item, hooks: hooks) }
                }
            }
        }
        if picture {
            row.frame(maxWidth: .infinity, alignment: .leading).clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var actionBar: some View {
        let chosen = model.selected
        // The machines show only for a selection with the device button there; the reset in body keeps `choosingDevice` in step with that.
        let choosing = choosingDevice && !chosen.isEmpty && buttons.showDevicesButton
        return HStack(spacing: 12) {
            if choosing {
                Text("Send to").font(.system(size: 11)).foregroundColor(Color(hex: "#B9BDC4"))
                deviceChips(chosen)
                // Cancel sits outside the row of machines, so it stays in view however many there are.
                ShelfBarButton(title: "Cancel", icon: "xmark") { choosingDevice = false }
            } else if chosen.isEmpty {
                Text(model.items.isEmpty ? "" : "Click a file to select it. Drag one out to use it anywhere.").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                Spacer()
            } else {
                Text(chosen.count == 1 ? "1 selected" : "\(chosen.count) selected").font(.system(size: 11)).foregroundColor(Color(hex: "#B9BDC4"))
                ShelfBarButton(title: "Ask", icon: "bubble.left", enabled: ShelfActionRules.canAsk(chosen, missing: model.missing), hint: ShelfActionRules.askHint) { if let one = chosen.first { buttons.ask(one) } }
                ShelfBarButton(title: "Send", icon: "square.and.arrow.up", enabled: ShelfActionRules.canSend(chosen, missing: model.missing), hint: "Send with the share sheet") { buttons.send(chosen) }
                ShelfBarButton(title: "AirDrop", icon: "antenna.radiowaves.left.and.right", enabled: ShelfActionRules.canSend(chosen, missing: model.missing), hint: "Send with AirDrop") { buttons.airDrop(chosen) }
                ShelfBarButton(title: "Show in Finder", icon: "folder", enabled: ShelfActionRules.canShow(chosen, missing: model.missing)) { buttons.show(chosen) }
                if buttons.showDevicesButton {
                    ShelfBarButton(title: "", icon: "laptopcomputer", enabled: ShelfActionRules.canSend(chosen, missing: model.missing), hint: "Send to another Mac or PC running NotchMeow", label: "Send to a device") { choosingDevice = true }
                }
                ShelfBarButton(title: "Remove", icon: "trash", tint: Color(hex: "#F4505E")) { model.remove(model.selection) }
                Spacer()
            }
        }
    }

    /// The paired machines as buttons. They sit in a row that scrolls when they do not fit (the picture, which cannot scroll, clips them at the bar's edge).
    @ViewBuilder private func deviceChips(_ chosen: [ShelfItem]) -> some View {
        let chips = HStack(spacing: 12) {
            if buttons.devices.isEmpty {
                Text("No paired machine yet").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                ShelfBarButton(title: "Set up Devices", icon: "gearshape") { choosingDevice = false; buttons.devicesHelp() }
            }
            ForEach(buttons.devices, id: \.id) { d in
                ShelfBarButton(title: d.name, icon: d.online ? "laptopcomputer" : "laptopcomputer.slash", enabled: d.online, hint: d.online ? "Send to \(d.name)" : "\(d.name) is not on the network", maxWidth: 140) {
                    choosingDevice = false
                    buttons.sendToDevice(chosen, d.id)
                }
            }
        }
        if picture {
            chips.frame(maxWidth: .infinity, alignment: .leading).clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) { chips }
        }
    }
}
