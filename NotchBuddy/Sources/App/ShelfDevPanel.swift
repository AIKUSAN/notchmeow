import AppKit
import SwiftUI

#if DEBUG && !APPSTORE

/// The Debug-only shelf panel (sub-project G1): the shelf view on a shelf of its own, the drop layer over a stand-in for the canvas with a switch for the half the pointer is over, and the compact
/// badge with the shelf's count. Opened from the menu bar's "Shelf (Debug)…". Nothing here touches the app's own shelf.
struct ShelfDevView: View {
    @StateObject private var dev: ShelfDevModel

    /// `root` is the folder the panel's shelf lives in; none (the app's panel) is a temp folder of its own that goes with the panel. The render script gives one inside its own scratch folder.
    init(root: URL? = nil) { _dev = StateObject(wrappedValue: ShelfDevModel(root: root)) }

    private var buttons: ShelfButtons {
        ShelfButtons(ask: { dev.say("Ask would start a new chat with \($0.name)") }, show: { items in
            dev.say("Show in Finder: \(items.count) item(s)")
            let opened = items.compactMap { dev.shelf.open($0) }
            NSWorkspace.shared.activateFileViewerSelecting(opened.map(\.url))
            for a in opened { a.end() }
        }, send: { dev.say("Send would open the share sheet for \($0.count) item(s)") }, airDrop: { dev.say("AirDrop would send \($0.count) item(s)") })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("The shelf") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Add three files") { dev.addSamples() }
                            Button("Add an image copy") { dev.addImageCopy() }
                            Button("Fill to 30") { dev.fill() }
                            Button("Drop two more") { dev.dropTwoMore() }
                            Button("Delete an original") { dev.deleteAnOriginal() }
                            Button("Clear") { dev.clear() }
                        }
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 22).fill(Color.black).frame(width: 640, height: 176)
                            RoundedRectangle(cornerRadius: 20).fill(Color(hex: "#141518")).frame(width: 620, height: 124).offset(x: 10, y: 42)
                            Circle().fill(Color(hex: "#C9A27E")).frame(width: 46, height: 46).offset(x: 31, y: 81)
                            ShelfContent(model: dev.shelf, hooks: .none, buttons: buttons).frame(width: 620, height: 124, alignment: .leading).offset(x: 10, y: 42)
                        }
                        .frame(width: 640, height: 176, alignment: .topLeading)
                        .accessibilityIdentifier(ShelfDevModel.marker)
                        ForEach(Array(dev.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11).monospaced()).foregroundColor(.secondary)
                        }
                    }.padding(6)
                }
                GroupBox("The drop halves") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $dev.half) {
                            Text("Pointer over Ask").tag(DropHalf.ask)
                            Text("Pointer over Shelf").tag(DropHalf.shelf)
                        }.pickerStyle(.segmented).frame(maxWidth: 320)
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(Color.black)
                            RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.051, green: 0.055, blue: 0.063)).frame(width: 620, height: 124).offset(x: 10, y: 42)
                            Text("Drop your files here").font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "#D5D7DB")).offset(x: 196, y: 82)
                            ShelfDropLayer(half: dev.half)
                        }
                        .frame(width: 640, height: 176, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        Text("A stand-in for the upload canvas: the layer is the real one. Nothing it draws is left of the centre line (scripts/render-shelf.sh --ask-check).")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }.padding(6)
                }
                GroupBox("The compact badge") {
                    HStack(spacing: 18) {
                        ForEach([0, 1, 12, 30], id: \.self) { n in
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).fill(Color.black).frame(width: 120, height: 32)
                                if ShelfBadge.isShown(compact: true, count: n, greetingTail: false) { ShelfBadgeView(count: n).position(x: 106, y: 16) }
                            }.frame(width: 120, height: 32)
                        }
                    }.padding(6)
                }
            }
            .padding(16)
        }
    }
}

#endif
