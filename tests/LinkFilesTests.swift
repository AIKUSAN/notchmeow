import Foundation

// The link's files (LinkFiles.swift): the sink's exclusive create, collisions, the private mode, quarantine and discard, and the source's refusals.
// Run it through scripts/test-link-files.sh. Everything happens in a temp folder.

@main
enum LinkFilesTests {
    static func mode(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.posixPermissions] as? Int) ?? -1 }

    @MainActor static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchmeow-link-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Downloads/NotchMeow", isDirectory: true)

        CT.section("the sink")
        let a = LinkFileSink(folder: folder, name: "report.pdf", quarantine: true)
        let ua = try! a.open()
        CT.check("the folder is made and the file takes its name, private while it is written", [ua.lastPathComponent, mode(ua)], ["report.pdf", 0o600] as [AnyHashable])
        try! a.write(Data("hello ".utf8)); try! a.write(Data("world".utf8))
        let done = try! a.finish()
        CT.check("what was written is on disk, and the file is ordinary and quarantined", [try! String(contentsOf: done, encoding: .utf8), mode(done), LinkFileSink.isQuarantined(done) ? 1 : 0] as [AnyHashable], ["hello world", 0o644, 1] as [AnyHashable])
        CT.check("it counted the bytes", a.written, 11)

        let b = LinkFileSink(folder: folder, name: "report.pdf", quarantine: false)
        let ub = try! b.open(); b.discard()
        CT.check("a second file of the same name is numbered, and a discarded one leaves nothing", [ub.lastPathComponent, FileManager.default.fileExists(atPath: ub.path) ? 1 : 0] as [AnyHashable], ["report (1).pdf", 0] as [AnyHashable])

        let c = LinkFileSink(folder: folder, name: "REPORT.PDF", quarantine: false)
        CT.check("another case of the name is a collision too (the usual volumes compare that way)", (try! c.open()).lastPathComponent, "REPORT (1).PDF")
        c.discard()

        // The volume says a name is taken that the listing did not show: a file made between the listing and the create. The sink must not overwrite it.
        let d = LinkFileSink(folder: folder, name: "race.txt", quarantine: false)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("race.txt").path, contents: Data("mine".utf8))
        let ud = try! d.open()
        CT.check("an existing file is never overwritten", [ud.lastPathComponent, try! String(contentsOf: folder.appendingPathComponent("race.txt"), encoding: .utf8)] as [AnyHashable], ["race (1).txt", "mine"] as [AnyHashable])
        d.discard()

        // A link in the folder with the wanted name: O_NOFOLLOW + O_EXCL refuse to write through it.
        let target = root.appendingPathComponent("elsewhere.txt"); FileManager.default.createFile(atPath: target.path, contents: Data("safe".utf8))
        try! FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.txt"), withDestinationURL: target)
        let e = LinkFileSink(folder: folder, name: "link.txt", quarantine: false)
        let ue = try! e.open()
        CT.check("a symbolic link with the wanted name is taken, not followed", [ue.lastPathComponent, try! String(contentsOf: target, encoding: .utf8)] as [AnyHashable], ["link (1).txt", "safe"] as [AnyHashable])
        e.discard()
        CT.checkTrue("the default folder is Downloads/NotchMeow", LinkFileSink.defaultFolder().path.hasSuffix("/Downloads/NotchMeow"))

        // A `defer { sink.discard() }` after a completed transfer must not delete the file.
        let g = LinkFileSink(folder: folder, name: "done.txt", quarantine: false)
        _ = try! g.open(); try! g.write(Data("whole".utf8))
        let gdone = try! g.finish()
        g.discard()
        CT.check("discard after finish keeps the completed file", [FileManager.default.fileExists(atPath: gdone.path) ? "kept" : "gone", (try? String(contentsOf: gdone, encoding: .utf8)) ?? "missing"], ["kept", "whole"])

        // A sink released without finish or discard leaves no partial file behind.
        var h: LinkFileSink? = LinkFileSink(folder: folder, name: "partial.bin", quarantine: false)
        let uh = try! h!.open(); try! h!.write(Data("half".utf8))
        h = nil
        CT.check("a sink released unfinished removes its partial file", FileManager.default.fileExists(atPath: uh.path) ? 1 : 0, 0)

        // Finished files are 0644 whatever the umask says (the mode is set on the open descriptor, not inherited).
        let old = umask(0o077)
        let m = LinkFileSink(folder: folder, name: "mode.txt", quarantine: false)
        _ = try! m.open(); try! m.write(Data("m".utf8))
        let mdone = try! m.finish()
        umask(old)
        CT.check("a finished file is 0644 even under a restrictive umask", mode(mdone), 0o644)

        // Names that would leave the folder are refused before anything is created.
        func refusedName(_ n: String) -> LinkFileSink.SinkError? {
            let s = LinkFileSink(folder: folder, name: n, quarantine: false)
            do { _ = try s.open(); s.discard(); return nil } catch { return error as? LinkFileSink.SinkError }
        }
        CT.check("a name with a slash is refused", refusedName("sub/x.txt"), LinkFileSink.SinkError.io(EINVAL))
        CT.check("a name with a backslash is refused", refusedName("a\\b.txt"), LinkFileSink.SinkError.io(EINVAL))
        CT.check("the name . is refused", refusedName("."), LinkFileSink.SinkError.io(EINVAL))
        CT.check("the name .. is refused", refusedName(".."), LinkFileSink.SinkError.io(EINVAL))
        CT.check("a refused name creates nothing in the folder", (try? FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("\\") || $0.hasPrefix("sub") }.count) ?? -1, 0)

        CT.section("the source")
        let file = root.appendingPathComponent("send me.txt"); try! Data("0123456789".utf8).write(to: file)
        let s = try! LinkFileSource(url: file)
        CT.check("name, size and a type that is ASCII", [s.name, "\(s.size)", s.kind] as [String], ["send me.txt", "10", "text/plain"])
        CT.check("it reads in pieces and ends with an empty one", [String(decoding: try! s.read(4), as: UTF8.self), String(decoding: try! s.read(4), as: UTF8.self), String(decoding: try! s.read(4), as: UTF8.self), "\(try! s.read(4).count)"], ["0123", "4567", "89", "0"])
        s.close()
        func refused(_ u: URL) -> LinkFileSource.SourceError? { do { _ = try LinkFileSource(url: u); return nil } catch { return error as? LinkFileSource.SourceError } }
        CT.check("a folder is refused", refused(folder), .notAFile)
        CT.check("a link to a folder is refused too", { try! FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dirlink"), withDestinationURL: folder); return refused(root.appendingPathComponent("dirlink")) }(), Optional(LinkFileSource.SourceError.notAFile))
        CT.check("a file that is not there is refused", refused(root.appendingPathComponent("nope")), .notAFile)
        let long = root.appendingPathComponent(String(repeating: "a", count: 200) + ".txt"); try! Data().write(to: long)
        CT.check("an empty file is a file (size 0)", try! LinkFileSource(url: long).size, 0)
        // A FIFO where a file was: refused, and the open must not wait for a writer (the test would hang if it did).
        let fifo = root.appendingPathComponent("pipe"); _ = mkfifo(fifo.path, 0o600)
        CT.check("a FIFO is refused without blocking", refused(fifo), .notAFile)
        CT.finish()
    }
}
