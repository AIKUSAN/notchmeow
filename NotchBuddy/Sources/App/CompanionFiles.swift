import Darwin
import Foundation

// The companion's files (F3a-mac, Task 3): owner-only folders and files under one root, atomic writes, reads that never follow a link, and the
// conversation ids on disk. Pure POSIX over Foundation, no logging: the errors carry no path and no text (Task 5 logs their kinds only).
struct CompanionFiles: Sendable {
    /// The marker of the companion's store in every build (scripts/check-app-binary.sh looks for it; Settings → Companion's sheet carries it).
    static let marker = "NM_COMPANION_STORE_ACTIVE"

    /// A conversation file larger than this is read as absent, and never overwritten without the user's action.
    static let conversationMax = 8 << 20

    /// The `companion` folder.
    let root: URL

    /// `<Application Support>/NotchMeow/companion` (the App Store build's container gives the same path).
    static func standard() -> CompanionFiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return CompanionFiles(root: support.appendingPathComponent("NotchMeow/companion", isDirectory: true))
    }

    var conversationsURL: URL {
        root.appendingPathComponent("conversations", isDirectory: true)
    }

    /// `conversations/<id>.json`, or nil when `id` is not a valid id: the one place a conversation's path is built, so no other name reaches disk.
    func conversationURL(_ id: String) -> URL? {
        guard CompanionRecords.isId(id) else { return nil }
        return conversationsURL.appendingPathComponent("\(id).json")
    }

    /// The bytes of a regular file of at most `maxBytes`, opened without following a link and without blocking (a FIFO is opened and refused by
    /// fstat). Nil for anything else: absent, a link, a folder, a FIFO, too large, or one that grows past the limit while it is read.
    func read(_ url: URL, maxBytes: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size <= maxBytes else { return nil }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if n == 0 { return data }
            data.append(chunk, count: n)
            if data.count > maxBytes { return nil }
        }
    }

    /// Writes `data` to `url` atomically: a new `.<name>.<random>.tmp` in the same folder (`O_EXCL`, `O_NOFOLLOW`, mode 0600), its bytes fsynced, then
    /// renamed over the target, then the folder fsynced (best effort). A link at the target is refused, and the temp file is removed on any failure.
    /// `companion/` and `conversations/` are made owner-only (0700) on every write, whatever the umask or a pre-existing mode says.
    func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        guard folder.standardizedFileURL.path == conversationsURL.standardizedFileURL.path else { throw CompanionFilesError.outsideRoot }
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ownerFolder(root)
        try ownerFolder(folder)
        guard fileType(url.path) != S_IFLNK else { throw CompanionFilesError.symbolicLink }
        let temp = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.lowercased()).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CompanionFilesError.io(errno) }
        var failure: Int32 = 0
        if !writeAll(fd, data) { failure = errno != 0 ? errno : EIO }
        if failure == 0, fsync(fd) != 0 { failure = errno }
        if close(fd) != 0, failure == 0 { failure = errno }
        if failure == 0, rename(temp, url.path) != 0 { failure = errno }
        if failure != 0 {
            _ = unlink(temp)
            throw CompanionFilesError.io(failure)
        }
        syncFolder(folder)
    }

    /// Removes the file at `url`. A link is removed, never followed. Returns 0 when it is gone (a file that was not there counts) and the errno when it stays.
    @discardableResult
    func delete(_ url: URL) -> Int32 {
        unlink(url.path) == 0 || errno == ENOENT ? 0 : errno
    }

    /// Removes the temp files a crashed write left: `.<name>.<random>.tmp` in the conversations folder (a conversation id never starts with a dot). Best effort.
    func sweepTemps() {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: conversationsURL.path)) ?? [] where name.hasPrefix(".") && name.hasSuffix(".tmp") {
            _ = unlink(conversationsURL.appendingPathComponent(name).path)
        }
    }

    /// Whether anything (a file, a folder or a link, pointing anywhere or nowhere) is at `url`.
    func exists(_ url: URL) -> Bool {
        fileType(url.path) != nil
    }

    /// The ids of the conversation files: `conversations/<id>.json` whose stem is a valid id. Other names are ignored, temp files included. A folder that
    /// is not there holds none; one that is there and cannot be listed is nil, never "none saved".
    func conversationIds() -> [String]? {
        guard exists(conversationsURL) else { return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: conversationsURL.path) else { return nil }
        return names.compactMap { name -> String? in
            guard name.hasSuffix(".json") else { return nil }
            let stem = String(name.dropLast(5))
            return CompanionRecords.isId(stem) ? stem : nil
        }.sorted()
    }

    /// Makes `url` a folder with mode 0700: created if absent, then chmod, so a pre-existing folder with a wider mode is corrected. A link or a file
    /// in its place is refused.
    private func ownerFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard fileType(url.path) == S_IFDIR else { throw CompanionFilesError.notAFolder }
        guard chmod(url.path, 0o700) == 0 else { throw CompanionFilesError.io(errno) }
    }

    /// Flushes the folder's entry after a rename. Best effort: a failure here does not undo the save.
    private func syncFolder(_ folder: URL) {
        let fd = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { return }
        _ = fsync(fd)
        _ = close(fd)
    }

    /// The file type of `path` as lstat sees it (a link is a link), or nil when nothing is there.
    private func fileType(_ path: String) -> mode_t? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return st.st_mode & S_IFMT
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: done), raw.count - done)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                done += n
            }
            return true
        }
    }
}

/// What a file operation refused or failed on. Carries no path and no text.
enum CompanionFilesError: Error, Equatable {
    case symbolicLink
    case notAFolder
    case outsideRoot
    case io(Int32)
}
