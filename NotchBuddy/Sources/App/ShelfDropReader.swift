import AppKit

// Reading what a drop on the Shelf half carries (sub-project G1). File URLs become links. A promised file (Mail, Photos, a screenshot thumbnail) is asked for into a fresh temp folder, and
// an image dragged out of a browser is written there as a PNG; both become copies on the shelf, and the caller removes the temp folder once the store has taken what it keeps. Only the
// drag's own file and image data are read: no URL on the pasteboard is ever fetched.

@MainActor
enum ShelfDropReader {
    /// The types the drop view registers for besides file URLs: what promised files are announced with, and raw image data.
    static var extraTypes: [NSPasteboard.PasteboardType] {
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [.tiff, .png]
    }

    /// What the pasteboard carries that the shelf can use.
    static func kinds(of pb: NSPasteboard) -> Set<DragKind> {
        var k: Set<DragKind> = []
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { k.insert(.fileURL) }
        if pb.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) { k.insert(.promisedFile) }
        if pb.types?.contains(where: { $0 == .png || $0 == .tiff }) == true { k.insert(.image) }
        return k
    }

    /// Collects the promised files as they arrive and finishes once the last one has. Main-actor isolated, so the receivers' callbacks (which run on `.main`) hop back to it.
    @MainActor private final class Collector {
        var items: [ShelfIncoming] = []
        private var receivers: [NSFilePromiseReceiver] = []   // kept alive until the files have arrived
        private var pending = 0
        private var armed = false
        private var finished = false
        private let folder: URL
        private let done: @MainActor ([ShelfIncoming], URL?) -> Void

        init(folder: URL, done: @escaping @MainActor ([ShelfIncoming], URL?) -> Void) { self.folder = folder; self.done = done }

        func expect(_ receiver: NSFilePromiseReceiver) { receivers.append(receiver); pending += 1 }

        func arrived(_ url: URL?) {
            pending -= 1
            if let url { items.append(.temporary(url)) }
            finishIfReady()
        }

        /// Everything is asked for: finish now if nothing is pending.
        func arm() { armed = true; finishIfReady() }

        private func finishIfReady() {
            guard armed, pending <= 0, !finished else { return }
            finished = true
            receivers.removeAll()
            done(items, folder)
        }
    }

    /// `done` gets the items and the temp folder holding the files received or written for this drop (nil for plain file URLs; the caller removes it when it is finished with the files).
    static func read(_ pb: NSPasteboard, kinds: Set<DragKind>, done: @escaping @MainActor ([ShelfIncoming], URL?) -> Void) {
        if kinds.contains(.fileURL) {
            let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            done(urls.map { .file($0) }, nil)
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchMeow-drop-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let box = Collector(folder: folder, done: done)
        var promised = 0
        if kinds.contains(.promisedFile) {
            for receiver in (pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? [] {
                promised += 1
                box.expect(receiver)
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                    Task { @MainActor in box.arrived(error == nil ? url : nil) }
                }
            }
        }
        if promised == 0, kinds.contains(.image), let png = imagePNG(pb) {
            let url = folder.appendingPathComponent("Image.png")
            if (try? png.write(to: url)) != nil { box.items.append(.temporary(url)) }
        }
        box.arm()
    }

    /// The image on the pasteboard as PNG bytes: the PNG itself, or the TIFF converted.
    static func imagePNG(_ pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        guard let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
