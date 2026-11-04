import CoreServices
import Foundation
import UniformTypeIdentifiers

// Files on the link (sub-project G2): where a received file is written and how, and how a file is read to be sent. Foundation only (and the quarantine call).
//
// Receiving. The folder is `~/Downloads/NotchMeow/`. The name is the sanitized one (`LinkName`), made free with `LinkName.uniqueName` and then **created exclusively** (`O_EXCL`): the sanitizer
// compares names the way the usual volumes do, but the volume decides which names are the same file, so on "already exists" the next free name is tried (docs/LINK-CONTRACT.md, known limits).
// The file is never followed through a link (`O_NOFOLLOW`), is created private (0600) and made ordinary (0644) only when it is complete, and is never opened. A transfer that does not
// complete leaves nothing behind (`discard`). On the GitHub build the quarantine attribute is set by hand when the file is created, so that even a partial file is quarantined;
// the App Store build is sandboxed, and the sandbox sets it.

final class LinkFileSink: @unchecked Sendable {
    enum SinkError: Error, Equatable { case noFolder, noFreeName, io(Int32) }

    let folder: URL
    private let wanted: String
    private let quarantine: Bool
    private var fd: Int32 = -1
    private var made: (dev: dev_t, ino: ino_t)?   // the file this sink created, so a discard never removes another file
    private var finished = false
    private(set) var url: URL?
    private(set) var written: UInt64 = 0

    #if APPSTORE
    static let quarantineByHand = false
    #else
    static let quarantineByHand = true
    #endif

    /// `~/Downloads/NotchMeow/` (the App Store build reaches it with `com.apple.security.files.downloads.read-write`).
    static func defaultFolder() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("NotchMeow", isDirectory: true)
    }

    init(folder: URL = LinkFileSink.defaultFolder(), name: String, quarantine: Bool = LinkFileSink.quarantineByHand) {
        self.folder = folder
        self.wanted = name
        self.quarantine = quarantine
    }

    /// A sink released before finish() is discarded: its partial file does not outlive it.
    deinit { discard() }

    /// Creates the file under a free name and returns its URL.
    func open() throws -> URL {
        // The wanted name is one file name in the folder, never a path (LinkName refuses these too; this is the second guard).
        guard !wanted.contains("/"), !wanted.contains("\\"), wanted != ".", wanted != ".." else { throw SinkError.io(EINVAL) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw SinkError.noFolder }
        var taken = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for _ in 0..<200 {
            guard let name = LinkName.uniqueName(wanted, taken: taken) else { throw SinkError.noFreeName }
            let target = folder.appendingPathComponent(name)
            let f = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            if f >= 0 {
                fd = f
                url = target
                var st = stat()
                if fstat(f, &st) == 0 { made = (dev: st.st_dev, ino: st.st_ino) }
                // GitHub build: a file that cannot be quarantined is not handed out; it goes, partial or not.
                if quarantine, !setQuarantine(target) {
                    discard()
                    throw SinkError.io(EIO)
                }
                return target
            }
            if errno == EEXIST { taken.append(name); continue }   // the volume says this name is taken: the next free one
            throw SinkError.io(errno)
        }
        throw SinkError.noFreeName
    }

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw SinkError.io(EBADF) }
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, data.count - offset) }
            if n < 0 { if errno == EINTR { continue }; throw SinkError.io(errno) }
            offset += n
        }
        written += UInt64(data.count)
    }

    /// The transfer is complete: make the file ordinary, then close it. Returns its URL. On failure the partial file is removed and this throws.
    @discardableResult
    func finish() throws -> URL {
        guard fd >= 0, let url else { throw SinkError.io(EBADF) }
        // The mode goes on the open descriptor, so it is the very file being closed that becomes ordinary.
        if fchmod(fd, 0o644) != 0 { let e = errno; discard(); throw SinkError.io(e) }
        let rc = close(fd)
        let e = errno
        fd = -1
        if rc != 0 { discard(); throw SinkError.io(e) }
        finished = true
        return url
    }

    /// The transfer did not complete: close and remove the partial file. After a successful finish() it does nothing, so a completed download stays.
    func discard() {
        guard !finished else { return }
        if fd >= 0 { close(fd); fd = -1 }
        removePartial()
        url = nil
    }

    /// Removes the partial file, unless the name now holds a different file (the user may have moved ours away).
    private func removePartial() {
        guard let url else { return }
        var st = stat()
        if let made, stat(url.path, &st) == 0, st.st_dev != made.dev || st.st_ino != made.ino { return }
        unlink(url.path)
    }

    private func setQuarantine(_ file: URL) -> Bool {
        var v = URLResourceValues()
        v.quarantineProperties = [kLSQuarantineAgentNameKey as String: "NotchMeow", kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String]
        var f = file
        return (try? f.setResourceValues(v)) != nil
    }

    /// Whether the file carries the quarantine attribute (the tests and the owner's check read it).
    static func isQuarantined(_ file: URL) -> Bool { getxattr(file.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0 }
}

/// A file read to be sent: a regular file of at most 4 GiB whose name fits the wire. A folder, a device, a link to either and a file that is too big are refused when the user clicks Send.
final class LinkFileSource: @unchecked Sendable {
    enum SourceError: Error, Equatable { case notAFile, tooLarge, nameTooLong, unreadable }

    let url: URL
    let name: String
    let size: UInt64
    let kind: String
    private var handle: FileHandle?

    init(url: URL) throws {
        // O_NONBLOCK: a FIFO swapped in after a name check cannot block this open. What was opened is then checked with fstat, not by the name.
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw (errno == ENOENT || errno == ENOTDIR) ? SourceError.notAFile : SourceError.unreadable }
        var keep = false
        defer { if !keep { Darwin.close(fd) } }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { throw SourceError.notAFile }
        guard UInt64(st.st_size) <= LinkWire.sizeMax else { throw SourceError.tooLarge }
        let name = url.lastPathComponent
        guard !name.isEmpty, name.utf8.count <= LinkWire.rawNameMax else { throw SourceError.nameTooLong }
        self.url = url
        self.name = name
        self.size = UInt64(st.st_size)
        self.handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        keep = true
        // Advisory only, never used to decide anything: the file's MIME type when it has one that is printable ASCII.
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
        self.kind = mime.utf8.count <= LinkWire.kindMax && mime.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) ? mime : ""
    }

    deinit { try? handle?.close() }

    /// The next piece, up to `count` bytes; empty at the end of the file.
    func read(_ count: Int) throws -> Data {
        guard let handle else { throw SourceError.unreadable }
        do { return try handle.read(upToCount: count) ?? Data() } catch { throw SourceError.unreadable }
    }

    func close() { try? handle?.close(); handle = nil }
}
