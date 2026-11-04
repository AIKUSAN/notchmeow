import Foundation

// MARK: - Kinds

/// Exact kinds from `attachment-cases.json` (`pdf` is refined into text or scanned by PDFKit).
enum AttachmentKind: String, Sendable, Equatable {
    case text, image, docx, rtf, html
    case pdfText = "pdf_text"
    case pdfScanned = "pdf_scanned"
}

enum AttachmentRejection: String, Error, Sendable, Equatable {
    case size, type
}

/// A dropped file, read once and ready to be turned into parts for any provider.
struct PreparedFile: Sendable, Equatable {
    let name: String
    let kind: AttachmentKind
    var mime: String = "text/plain"
    /// Original bytes, for PDFs and images.
    var data: Data? = nil
    /// The text: file text, extracted PDF/docx/rtf/html text, or OCR of an image or scanned PDF.
    var text: String? = nil
    /// First pages of a scanned PDF, as PNG.
    var pageImages: [Data] = []
}

// MARK: - Classification (reference.py classify_file)

enum AttachmentRules {
    static let rejectExtensions: Set<String> = ["zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "msi",
                                                "exe", "app", "mov", "mp4", "mkv", "avi"]
    static let imageMIME: [String: String] = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                              "gif": "image/gif", "webp": "image/webp", "heic": "image/heic"]

    /// Before PDFKit: `pdf` is not yet split into text and scanned.
    enum Coarse: Sendable, Equatable {
        case text, pdf, docx, rtf, html
        case image(mime: String)
    }

    static func classify(url: URL) -> Result<Coarse, AttachmentRejection> {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var head = Data()
        if size <= AICatalog.Limits.maxFileBytes, let handle = try? FileHandle(forReadingFrom: url) {
            head = (try? handle.read(upToCount: 8192)) ?? Data()
            try? handle.close()
        }
        return classify(size: size, ext: url.pathExtension, head: head)
    }

    /// Rules in order: size; extension (lowercased); otherwise the first 8 KB must be UTF-8 without NUL.
    static func classify(size: Int, ext: String, head: Data) -> Result<Coarse, AttachmentRejection> {
        if size > AICatalog.Limits.maxFileBytes { return .failure(.size) }
        let e = ext.lowercased()
        switch e {
        case "pdf": return .success(.pdf)
        case "docx": return .success(.docx)
        case "rtf": return .success(.rtf)
        case "html", "htm": return .success(.html)
        default: break
        }
        if let mime = imageMIME[e] { return .success(.image(mime: mime)) }
        if rejectExtensions.contains(e) || head.contains(0) { return .failure(.type) }
        // A multi-byte character cut by the 8 KB read is fine: an error in the last 3 bytes is allowed.
        let valid = (0...min(3, head.count)).contains { String(data: head.dropLast($0), encoding: .utf8) != nil }
        return valid ? .success(.text) : .failure(.type)
    }

    /// Tag strip: drops script/style/comments, keeps block breaks as spaces, decodes entities,
    /// collapses whitespace runs to single spaces. No WebKit, so no network.
    static func htmlToText(_ html: String) -> String {
        var s = html
        let rules: [(String, String)] = [
            ("(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", " "),
            ("(?s)<!--.*?-->", " "),
            ("(?i)</?(p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|header|footer|blockquote|pre)\\b[^>]*>", " "),
            ("<[^>]+>", ""),
        ]
        for (pattern, template) in rules {
            let re = try! NSRegularExpression(pattern: pattern)
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        s = decodeEntities(s)
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func decodeEntities(_ text: String) -> String {
        var s = text
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for m in numeric.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let hex = (s as NSString).substring(with: m.range(at: 1)) == "x"
            let digits = (s as NSString).substring(with: m.range(at: 2))
            if let v = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(v),
               let r = Range(m.range, in: s) {
                s.replaceSubrange(r, with: String(Character(scalar)))
            }
        }
        return s.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - What each provider receives (spec §3)

enum AttachmentPlan {
    /// Image types every vision API accepts (HEIC is converted to JPEG when the file is read).
    static let sendableImageTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]

    /// The parts for one file and one model, plus the truncation notice shown to the user.
    /// Anthropic, OpenAI and Claude Code read PDFs natively (all see page images); other vision models get
    /// images; everything else gets text cut to the model's budget.
    static func parts(for file: PreparedFile, api: AIProviderAPI, vision: Bool,
                      placement: AIPlacement, contextTokens: Int?) -> (parts: [ChatRequest.Part], notice: String?) {
        let nativePDF = vision && (api == .anthropic || api == .openaiResponses || api == .claudeCode)
        func text(_ t: String?) -> ([ChatRequest.Part], String?) {
            let cut = ContextBudget.cut(t ?? "", placement: placement, contextTokens: contextTokens)
            let body = cut.notice.map { "\(cut.text)\n\n(\($0))" } ?? cut.text
            return ([.fileText(name: file.name, text: body)], cut.notice)
        }
        switch file.kind {
        case .text, .docx, .rtf, .html:
            return text(file.text)
        case .pdfText:
            if nativePDF, let data = file.data { return ([.pdf(name: file.name, data: data)], nil) }
            return text(file.text)
        case .pdfScanned:
            if nativePDF, let data = file.data { return ([.pdf(name: file.name, data: data)], nil) }
            if vision, !file.pageImages.isEmpty {
                return ([.text("File: \(file.name)")] + file.pageImages.map { .image(mime: "image/png", data: $0) }, nil)
            }
            return text(file.text)
        case .image:
            if vision, let data = file.data, sendableImageTypes.contains(file.mime) {
                return ([.text("File: \(file.name)"), .image(mime: file.mime, data: data)], nil)
            }
            return text(file.text)
        }
    }
}
