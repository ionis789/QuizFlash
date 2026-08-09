//
//  AISourcePreparationService.swift
//  QuizFlash
//

import Foundation
import UIKit

/// One previewable source item shown inside the AI generation sheet.
struct AIGenerationSourcePreviewItem: Identifiable {
    let id = UUID()
    let index: Int
    let title: String
    let characterCount: Int
    let thumbnail: UIImage?
}

/// Fully prepared source payload reused by the generation sheet and the final
/// AI pipeline so extraction is performed exactly once.
struct AIPreparedGenerationSource {
    enum Kind {
        case photos
        case pdf
    }

    let kind: Kind
    let previewItems: [AIGenerationSourcePreviewItem]
    let textSegments: [AITextSourceSegment]
    let images: [UIImage]
    let pdfURL: URL?
    let needsOCRCorrection: Bool

    var isPDF: Bool { kind == .pdf }
    var itemCount: Int { previewItems.count }
    var totalCharacterCount: Int { previewItems.reduce(0) { $0 + $1.characterCount } }
    var itemLabels: [String] { previewItems.map(\.title) }
}

/// Prepared PDF payload plus the analysis metadata displayed by the normal
/// generation sheet.
struct AIPreparedPDFSource {
    let source: AIPreparedGenerationSource
    let analysis: PDFAnalysisInfo
}

/// Failures produced while converting an imported source into usable text.
nonisolated enum AISourcePreparationError: LocalizedError {
    case unusableText

    var errorDescription: String? {
        "Could not extract text from this source. Try another source."
    }
}

/// The single production owner for PDF and photo preparation. Both the normal
/// deck flow and diagnostics must call this type so OCR and page routing cannot
/// diverge between surfaces.
enum AISourcePreparationService {
    /// Decodes and bounds a selected photo exactly as the production picker
    /// does before OCR begins.
    static func decodePreparedPhoto(from data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = autoreleasepool {
                    UIImage(data: data)?.resizedForAI(toMaxDimension: 1024)
                }
                continuation.resume(returning: image)
            }
        }
    }

    static func preparePhotos(_ images: [UIImage]) async throws -> AIPreparedGenerationSource {
        let texts = await DocumentTextExtractor.extractFastVisionTexts(from: images)
        try Task.checkCancellation()
        guard DocumentTextExtractor.isUsableExtractedText(texts) else {
            throw AISourcePreparationError.unusableText
        }

        let orderedPayload = reorderedPhotoPayloadIfDocumentPagesDetected(
            images: images,
            texts: texts
        )
        return AIPreparedGenerationSource(
            kind: .photos,
            previewItems: makePhotoPreviewItems(
                images: orderedPayload.images,
                texts: orderedPayload.texts
            ),
            textSegments: makeTextSegments(from: orderedPayload.texts, labelPrefix: "Image"),
            images: orderedPayload.images,
            pdfURL: nil,
            needsOCRCorrection: DocumentTextExtractor.needsAICorrectionForExtractedText(
                orderedPayload.texts
            )
        )
    }

    static func preparePDF(from localURL: URL) async throws -> AIPreparedPDFSource {
        var pageTexts = await extractPDFKitPageTexts(from: localURL)
        var needsOCRCorrection = DocumentTextExtractor.needsAICorrectionForExtractedText(pageTexts)
        PDFImportDebugStore.record(
            "preparePDFSource pdfkit extracted",
            details: [
                "pages": String(pageTexts.count),
                "chars": String(pageTexts.reduce(0) { $0 + $1.count }),
                "usable": String(DocumentTextExtractor.isUsableExtractedText(pageTexts))
            ]
        )
        await Task.yield()

        if !DocumentTextExtractor.isUsableExtractedText(pageTexts) {
            PDFImportDebugStore.record("preparePDFSource ocr fallback start")
            pageTexts = await DocumentTextExtractor.extractVisionTextsFromPDFPages(from: localURL)
            needsOCRCorrection = true
            PDFImportDebugStore.record(
                "preparePDFSource ocr fallback finished",
                details: [
                    "pages": String(pageTexts.count),
                    "chars": String(pageTexts.reduce(0) { $0 + $1.count }),
                    "usable": String(DocumentTextExtractor.isUsableExtractedText(pageTexts))
                ]
            )
            await Task.yield()
        }

        try Task.checkCancellation()
        guard DocumentTextExtractor.isUsableExtractedText(pageTexts) else {
            PDFImportDebugStore.record("preparePDFSource failed unusable text")
            throw AISourcePreparationError.unusableText
        }

        let thumbnails = await DocumentTextExtractor.renderPDFPreviewThumbnails(from: localURL)
        PDFImportDebugStore.record(
            "preparePDFSource thumbnails",
            details: ["count": String(thumbnails.count)]
        )
        await Task.yield()
        let pageCount = max(pageTexts.count, await extractPDFPageCount(from: localURL))
        let extractedChars = pageTexts.reduce(0) { $0 + $1.count }
        let analysis = PDFAnalysisInfo(
            quality: await extractPDFQuality(from: localURL),
            pageCount: pageCount,
            extractedChars: extractedChars
        )
        let source = AIPreparedGenerationSource(
            kind: .pdf,
            previewItems: makePDFPreviewItems(
                pageTexts: pageTexts,
                pageCount: pageCount,
                thumbnails: thumbnails
            ),
            textSegments: makeTextSegments(from: pageTexts, labelPrefix: "Page"),
            images: [],
            pdfURL: localURL,
            needsOCRCorrection: needsOCRCorrection
        )
        return AIPreparedPDFSource(source: source, analysis: analysis)
    }

    static func makePhotoPreviewItems(
        images: [UIImage],
        texts: [String]
    ) -> [AIGenerationSourcePreviewItem] {
        images.enumerated().map { index, image in
            let text = texts.indices.contains(index) ? texts[index] : ""
            return AIGenerationSourcePreviewItem(
                index: index + 1,
                title: "Image \(index + 1)",
                characterCount: text.count,
                thumbnail: image.resizedForAI(toMaxDimension: 240)
            )
        }
    }

    static func makePDFPreviewItems(
        pageTexts: [String],
        pageCount: Int,
        thumbnails: [UIImage]
    ) -> [AIGenerationSourcePreviewItem] {
        let totalPages = max(pageCount, pageTexts.count)
        return (0 ..< totalPages).map { index in
            let text = pageTexts.indices.contains(index) ? pageTexts[index] : ""
            return AIGenerationSourcePreviewItem(
                index: index + 1,
                title: "Page \(index + 1)",
                characterCount: text.count,
                thumbnail: thumbnails.indices.contains(index) ? thumbnails[index] : nil
            )
        }
    }

    static func makeTextSegments(
        from texts: [String],
        labelPrefix: String
    ) -> [AITextSourceSegment] {
        texts.enumerated().map { index, text in
            AITextSourceSegment(
                index: index + 1,
                label: "\(labelPrefix) \(index + 1)",
                text: text
            )
        }
    }

    static func reorderedPhotoPayloadIfDocumentPagesDetected(
        images: [UIImage],
        texts: [String]
    ) -> (images: [UIImage], texts: [String]) {
        guard let indices = documentPageReorderedIndices(for: texts) else {
            return (images, texts)
        }

        let orderedTexts = indices.compactMap { texts.indices.contains($0) ? texts[$0] : nil }
        let orderedImages = indices.compactMap { images.indices.contains($0) ? images[$0] : nil }
        guard orderedTexts.count == texts.count,
              orderedImages.count == images.count else {
            return (images, texts)
        }
        return (orderedImages, orderedTexts)
    }

    static func documentPageReorderedIndices(for texts: [String]) -> [Int]? {
        guard texts.count > 1 else { return nil }

        let detections = texts.enumerated().compactMap { index, text -> (index: Int, page: Int, total: Int)? in
            guard let footer = detectedDocumentPageFooter(in: text) else { return nil }
            return (index, footer.page, footer.total)
        }
        guard !detections.isEmpty else { return nil }

        let groupedByTotal = Dictionary(grouping: detections, by: \.total)
        guard let dominant = groupedByTotal.max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }

        let minimumDetectedCount = min(
            texts.count,
            max(3, Int((Double(texts.count) * 0.45).rounded(.up)))
        )
        guard dominant.value.count >= minimumDetectedCount else {
            return nil
        }

        let pagesByIndex = Dictionary(uniqueKeysWithValues: dominant.value.map { ($0.index, $0.page) })
        let sortedIndices = texts.indices.sorted { lhs, rhs in
            let lhsPage = pagesByIndex[lhs]
            let rhsPage = pagesByIndex[rhs]

            switch (lhsPage, rhsPage) {
            case let (lhsPage?, rhsPage?):
                return lhsPage == rhsPage ? lhs < rhs : lhsPage < rhsPage
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs < rhs
            }
        }
        return sortedIndices == Array(texts.indices) ? nil : sortedIndices
    }

    private static func extractPDFKitPageTexts(from url: URL) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.extractPDFKitPages(from: url))
            }
        }
    }

    private static func extractPDFPageCount(from url: URL) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.pdfPageCount(url: url))
            }
        }
    }

    private static func extractPDFQuality(from url: URL) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: DocumentTextExtractor.pdfKitQuality(for: url))
            }
        }
    }

    private static func detectedDocumentPageFooter(in text: String) -> (page: Int, total: Int)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(10)

        for line in lines.reversed() {
            if let explicit = pageFooterMatch(
                in: line,
                pattern: #"(?<!\d)([1-9]\d{0,2})\s*[/\\|]\s*([1-9]\d{1,2})(?!\d)"#
            ) {
                return explicit
            }

            let compact = line.replacingOccurrences(
                of: #"\s+"#,
                with: "",
                options: .regularExpression
            )
            if let collapsed = pageFooterMatch(
                in: compact,
                pattern: #"^([1-9]\d{0,2})[1Il|/\\]([1-9]\d{1,2})$"#
            ) {
                return collapsed
            }
        }
        return nil
    }

    private static func pageFooterMatch(
        in text: String,
        pattern: String
    ) -> (page: Int, total: Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 3,
              let pageRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text),
              let page = Int(text[pageRange]),
              let total = Int(text[totalRange]),
              total >= 2,
              page >= 1,
              page <= total else {
            return nil
        }
        return (page, total)
    }
}
