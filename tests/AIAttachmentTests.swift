import Foundation
import ImageIO
import PDFKit

@main
@MainActor
enum AIAttachmentTests {
    static func main() {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        attachmentCases(dir)
        lockedPDF(dir)
        heic(dir)
        readOnce(dir)
        plan(dir)
        html()
        T.finish()
    }

    static func attachmentCases(_ dir: URL) {
        T.section("attachment-cases.json")
        for c in T.fixture("attachment-cases.json")["cases"] as! [[String: Any]] {
            let file = c["file"] as! String
            let kind = c["kind"] as! String
            switch AttachmentExtractor.prepare(url: dir.appendingPathComponent(file)) {
            case .failure(let reason):
                T.check("\(file) → \(kind)", "rejected \(reason.rawValue)", "rejected \(c["reason"] as? String ?? "?")")
            case .success(let prepared):
                T.check("\(file) → \(kind)", prepared.kind.rawValue, kind)
                for needle in c["contains"] as? [String] ?? [] {
                    T.checkTrue("\(file) contains \"\(needle)\"", prepared.text?.contains(needle) == true)
                }
                for needle in c["notContains"] as? [String] ?? [] {
                    T.checkTrue("\(file) leaves out \"\(needle)\"", prepared.text?.contains(needle) == false)
                }
                if let mime = c["mime"] as? String { T.check("\(file) mime", prepared.mime, mime) }
            }
        }
    }

    /// Bank statements are often password-protected: rejected, not sent half-read.
    static func lockedPDF(_ dir: URL) {
        T.section("Locked PDF")
        let doc = PDFDocument(url: dir.appendingPathComponent("text.pdf"))!
        let locked = dir.appendingPathComponent("locked.pdf")
        doc.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"])
        let result = AttachmentExtractor.prepare(url: locked)
        T.checkTrue("a password-protected PDF is rejected", result == .failure(.type))
    }

    /// iPhone photos are HEIC: they reach the APIs as JPEG.
    static func heic(_ dir: URL) {
        T.section("HEIC")
        let png = try! Data(contentsOf: dir.appendingPathComponent("photo.png"))
        let heicURL = dir.appendingPathComponent("photo.heic")
        guard let image = AttachmentExtractor.cgImage(png),
              let destination = CGImageDestinationCreateWithURL(heicURL as CFURL, "public.heic" as CFString, 1, nil) else {
            print("  · no HEIC encoder on this machine, skipped")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { print("  · no HEIC encoder on this machine, skipped"); return }
        let prepared = try? AttachmentExtractor.prepare(url: heicURL).get()
        T.check("HEIC is sent as JPEG", prepared?.mime, "image/jpeg")
        T.check("with JPEG bytes", prepared?.data?.prefix(2).map { $0 }, [0xFF, 0xD8])
    }

    /// A dropped file is read once, at the drop. If its inbox copy is cleaned up afterwards, the messages
    /// that follow still carry the file: nothing opens it again.
    static func readOnce(_ dir: URL) {
        T.section("A prepared file is read once")
        let copy = dir.appendingPathComponent("inbox-copy.txt")
        try! "Shrimpy's notes".write(to: copy, atomically: true, encoding: .utf8)
        let prepared = try! AttachmentExtractor.prepare(url: copy).get()
        try! FileManager.default.removeItem(at: copy)
        for message in 1...3 {
            let parts = AttachmentPlan.parts(for: prepared, api: .openaiChat, vision: false, placement: .local,
                                             contextTokens: nil).parts
            T.check("message \(message) still gets the file after the original is gone", parts,
                    [.fileText(name: "inbox-copy.txt", text: "Shrimpy's notes")])
        }
        T.checkTrue("opening the missing file again fails cleanly", AttachmentExtractor.prepare(url: copy) == .failure(.type))
    }

    static func describe(_ parts: [ChatRequest.Part]) -> [String] {
        parts.map {
            switch $0 {
            case .text: "text"
            case .fileText: "fileText"
            case .image(let mime, _): "image \(mime)"
            case .pdf: "pdf"
            }
        }
    }

    static func plan(_ dir: URL) {
        T.section("AttachmentPlan (spec §3 table)")
        let pdf = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("text.pdf")).get()
        let scan = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("scan.pdf")).get()
        let png = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("photo.png")).get()
        func p(_ f: PreparedFile, _ api: AIProviderAPI, vision: Bool, _ placement: AIPlacement = .local) -> [String] {
            describe(AttachmentPlan.parts(for: f, api: api, vision: vision, placement: placement, contextTokens: nil).parts)
        }
        T.check("text PDF → Anthropic native", p(pdf, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("text PDF → OpenAI native", p(pdf, .openaiResponses, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Claude Code native", p(pdf, .claudeCode, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Google text", p(pdf, .openaiChat, vision: true, .cloud), ["fileText"])
        T.check("text PDF → local text", p(pdf, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → vision local gets pages", p(scan, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("scanned PDF → text-only local gets OCR", p(scan, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → Anthropic native", p(scan, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("image → Claude Code gets the image", p(png, .claudeCode, vision: true, .cloud), ["text", "image image/png"])
        T.check("image → vision model", p(png, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("image → Apple gets OCR text", p(png, .apple, vision: false), ["fileText"])
        let heic = PreparedFile(name: "x.heic", kind: .image, mime: "image/heic", data: Data([1]), text: "words")
        T.check("an unconverted HEIC never reaches Anthropic", p(heic, .anthropic, vision: true, .cloud), ["fileText"])

        let long = PreparedFile(name: "long.txt", kind: .text,
                                text: String(repeating: String(repeating: "a", count: 9) + "\n", count: 1000))
        let cut = AttachmentPlan.parts(for: long, api: .openaiChat, vision: false, placement: .local, contextTokens: nil)
        T.check("long text is cut with a notice", cut.notice, "I read the first 716 lines.")
        if case .fileText(_, let body) = cut.parts.first {
            T.checkTrue("the model is told too", body.hasSuffix("(I read the first 716 lines.)"))
        } else {
            T.checkTrue("long text gives a fileText part", false)
        }
    }

    static func html() {
        T.section("AttachmentRules.htmlToText")
        T.check("entities and blocks", AttachmentRules.htmlToText("<p>Tom&nbsp;&amp;&#32;Jerry</p><p>&#x1F431;</p>"),
                "Tom & Jerry 🐱")
        T.check("inline tags join words", AttachmentRules.htmlToText("N<b>otch</b>Meow"), "NotchMeow")
        T.check("comments dropped", AttachmentRules.htmlToText("a<!-- secret -->b"), "a b")
    }
}
