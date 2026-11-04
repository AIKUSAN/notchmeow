import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

/// Reads a dropped file once: text, PDF text layer or page images, docx/rtf text, image OCR.
/// Synchronous and slow on big files: call it off the main thread.
enum AttachmentExtractor {
    static let maxPDFPagesAsImages = 3
    /// Long edge for rendered pages, as recommended for Claude vision input.
    static let pageImageLongEdge: CGFloat = 1568

    static func prepare(url: URL) -> Result<PreparedFile, AttachmentRejection> {
        let name = url.lastPathComponent
        switch AttachmentRules.classify(url: url) {
        case .failure(let reason):
            return .failure(reason)
        case .success(.text):
            guard let data = try? Data(contentsOf: url) else { return .failure(.type) }
            return .success(PreparedFile(name: name, kind: .text, text: String(decoding: data, as: UTF8.self)))
        case .success(.html):
            guard let data = try? Data(contentsOf: url) else { return .failure(.type) }
            return .success(PreparedFile(name: name, kind: .html,
                                         text: AttachmentRules.htmlToText(String(decoding: data, as: UTF8.self))))
        case .success(.docx):
            return documentText(url: url, type: .officeOpenXML).map {
                .success(PreparedFile(name: name, kind: .docx, text: $0))
            } ?? .failure(.type)
        case .success(.rtf):
            return documentText(url: url, type: .rtf).map {
                .success(PreparedFile(name: name, kind: .rtf, text: $0))
            } ?? .failure(.type)
        case .success(.pdf):
            // A password-protected PDF can't be read here, and the APIs refuse it too.
            guard let data = try? Data(contentsOf: url), let doc = PDFDocument(data: data), !doc.isLocked else {
                return .failure(.type)
            }
            let layer = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !layer.isEmpty {
                return .success(PreparedFile(name: name, kind: .pdfText, mime: "application/pdf", data: data, text: layer))
            }
            let pages = renderPages(doc)
            let ocr = pages.compactMap { NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .map(recognizeText).joined(separator: "\n")
            return .success(PreparedFile(name: name, kind: .pdfScanned, mime: "application/pdf", data: data,
                                         text: ocr, pageImages: pages))
        case .success(.image(let mime)):
            guard let data = try? Data(contentsOf: url), let cg = cgImage(data) else { return .failure(.type) }
            // Anthropic and OpenAI don't take HEIC: re-encode it as JPEG. If that fails, no image goes
            // out and models get the recognised text instead.
            if mime == "image/heic" {
                return .success(PreparedFile(name: name, kind: .image, mime: "image/jpeg", data: jpeg(cg),
                                             text: recognizeText(cg)))
            }
            return .success(PreparedFile(name: name, kind: .image, mime: mime, data: data, text: recognizeText(cg)))
        }
    }

    /// docx / rtf through the system importer (no network for these formats).
    static func documentText(url: URL, type: NSAttributedString.DocumentType) -> String? {
        guard let attributed = try? NSAttributedString(url: url, options: [.documentType: type],
                                                       documentAttributes: nil) else { return nil }
        return attributed.string
    }

    /// The first pages as PNG, long edge at most 1,568 px.
    static func renderPages(_ doc: PDFDocument) -> [Data] {
        (0..<min(doc.pageCount, maxPDFPagesAsImages)).compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(pageImageLongEdge / max(bounds.width, bounds.height, 1), 4)
            let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
    }

    /// On-device text recognition (Vision). Empty when nothing readable.
    static func recognizeText(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// First frame of any image ImageIO reads (PNG, JPEG, GIF, WebP, HEIC).
    static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// JPEG through ImageIO (quality 0.85).
    static func jpeg(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
