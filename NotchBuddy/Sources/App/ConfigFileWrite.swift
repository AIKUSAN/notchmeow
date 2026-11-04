import Foundation

// How NotchMeow writes another tool's config file: Claude Code's settings.json, Gemini's settings.json, Codex's and Antigravity's hooks.json. A dotfiles setup often makes such a file a symbolic
// link, and Foundation's atomic write replaces a link with a plain file (with the link's own permissions, 0755) and leaves the file it pointed at as it was. So a write goes to the file the link
// points at, which keeps the link and that file's permissions, and a dated backup holds that file's text, not a second link to it that the write would then change. Foundation only.

enum ConfigFileWrite {
    /// The file a write to `url` changes: `url` itself, or the file at the end of its chain of symbolic links (a link to a file that is not there yet ends at the place it points to). A relative link is
    /// read from the folder it really sits in, and the chain is cut after 32 links, which also ends a loop.
    static func resolved(_ url: URL) -> URL {
        var url = url
        for _ in 0..<32 {
            let dir = url.deletingLastPathComponent().resolvingSymlinksInPath()
            url = dir.appendingPathComponent(url.lastPathComponent)
            guard let to = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return url }
            url = URL(fileURLWithPath: to, relativeTo: dir).absoluteURL.standardizedFileURL
        }
        return url
    }

    /// Copies the file `url` stands for to `backup`: its text, never a link to it. Throws like `FileManager.copyItem`.
    static func backUp(_ url: URL, to backup: URL) throws {
        try FileManager.default.copyItem(at: resolved(url), to: backup)
    }

    /// Replaces the file `url` stands for with `data`, atomically, making its folder if need be. An atomic write to a plain file keeps that file's permissions, which is why it is made to the file at the
    /// end of the links and not to the link.
    static func write(_ data: Data, to url: URL) throws {
        let target = resolved(url)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    /// Reads the JSON object in the file at `url` before a writer changes it. A file that is not there, or holds only whitespace, is an empty object. A file that is there but cannot be read, or is not a
    /// JSON object (comments, a trailing comma, a truncated write), throws a message that names `label` and says nothing was touched: a writer that started from [:] instead would drop everything else
    /// the user keeps in that file.
    static func readObject(at url: URL, label: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        func refuse(_ why: String) -> NSError {
            NSError(domain: "NotchMeow", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(label) \(why) — NotchMeow has not touched it."])
        }
        guard let data = try? Data(contentsOf: url) else { throw refuse("cannot be read") }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw refuse("is not valid JSON") }
        return object
    }

    /// `write`, after a dated backup of the file that is there: `<suffix>.bak-yyyyMMdd-HHmmss` beside it (`-1`, `-2` ... if that name is taken), made through `backUp`, so a link's backup holds the text. A
    /// backup that cannot be made stops the write and throws; the file is not touched. Returns the backup's file name, or nil when there was no file to back up.
    @discardableResult
    static func writeWithBackup(_ data: Data, to url: URL, suffix: String, now: Date = Date()) throws -> String? {
        var name: String?
        if FileManager.default.fileExists(atPath: url.path) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyyMMdd-HHmmss"
            let base = "\(suffix).bak-\(fmt.string(from: now))", dir = url.deletingLastPathComponent()
            var candidate = base, n = 0
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) { n += 1; candidate = "\(base)-\(n)" }
            do { try backUp(url, to: dir.appendingPathComponent(candidate)) }
            catch {
                throw NSError(domain: "NotchMeow", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not back up \(url.lastPathComponent): \(error.localizedDescription)"])
            }
            name = candidate
        }
        try write(data, to: url)
        return name
    }
}
