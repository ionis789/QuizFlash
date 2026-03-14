//
//  DocumentTextExtractor.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.02.2026.
//

import Foundation
import UIKit
import PDFKit
import Vision

// MARK: - ExtractionMethod

/// Describes the strategy used to extract textual content from a document.
///
/// The extraction pipeline is hierarchical and attempts progressively more
/// expensive strategies depending on document structure.
enum ExtractionMethod {
    
    /// Text was extracted directly from the PDF’s embedded text layer.
    /// Fast, free, and preferred when available.
    case pdfKit
    
    /// Text was extracted using on-device Vision OCR.
    /// Used for scanned PDFs or image-based documents.
    case visionOCR
    
    /// Raw images were returned because local extraction quality was insufficient.
    /// Intended for cloud-based processing (e.g., GPT Vision).
    case rawImages
}

// MARK: - ExtractionResult

/// Represents the final output of the document extraction pipeline.
///
/// The result contains either extracted text or raw images,
/// depending on the extraction strategy that succeeded.
struct ExtractionResult {
    
    /// Extracted textual content.
    /// `nil` only when the method is `.rawImages`.
    let text: String?
    
    /// Rendered document images.
    /// Present only when `.rawImages` fallback is used.
    let images: [UIImage]?
    
    /// The extraction strategy that produced the result.
    let method: ExtractionMethod
    
    /// Total number of pages processed.
    let pageCount: Int
    
    /// Indicates whether the result contains usable text.
    var isTextBased: Bool {
        method == .pdfKit || method == .visionOCR
    }
    
    /// Indicates whether OCR correction may be required.
    var needsOCRCorrection: Bool {
        method == .visionOCR
    }
}

// MARK: - DocumentTextExtractor

/// A multi-stage document text extraction pipeline.
///
/// Designed for production usage in QuizFlash, this extractor:
/// - Maximizes performance
/// - Minimizes cost
/// - Falls back gracefully
/// - Preserves architectural separation
///
/// Extraction Strategy:
///
/// 1. **PDFKit Extraction**
///    Attempts to extract embedded text directly from the PDF.
///    Fastest and most reliable when text is digitally embedded.
///
/// 2. **Vision OCR**
///    Performs on-device OCR for scanned PDFs or images.
///    Free and privacy-friendly.
///
/// 3. **Raw Image Fallback**
///    Returns rendered images for cloud-based AI processing.
///
/// This actor ensures thread safety and isolates document processing work.
actor DocumentTextExtractor {
    
    // MARK: - Extraction Thresholds
    
    /// Minimum character count required to consider PDFKit extraction successful.
    private static let minimumPDFTextLength = 100
    
    /// Minimum average characters per page required to consider OCR acceptable.
    private static let minimumOCRCharsPerPage = 30

    /// Stable page delimiter reused by the AI chunking layer.
    static let pageSeparator = "\n\n--- Next Page ---\n\n"
    
    // MARK: - Public Entry Points
    
    /// Extracts content from a PDF file URL.
    ///
    /// - Parameter pdfURL: The local file URL of the PDF.
    /// - Returns: An `ExtractionResult` describing the outcome.
    static func extract(from pdfURL: URL) async -> ExtractionResult {
        
        let pageCount = await pdfPageCount(url: pdfURL)
        
        // Stage 1: PDFKit
        if let text = extractWithPDFKit(from: pdfURL),
           text.count >= minimumPDFTextLength {
            
            return ExtractionResult(
                text: text,
                images: nil,
                method: .pdfKit,
                pageCount: pageCount
            )
        }
        
        // Stage 2: Vision OCR
        let images = await renderPDFPages(from: pdfURL)
        
        if !images.isEmpty {
            let ocrText = await extractWithVision(from: images)
            let averageChars = ocrText.count / max(images.count, 1)
            
            if averageChars >= minimumOCRCharsPerPage {
                return ExtractionResult(
                    text: ocrText,
                    images: nil,
                    method: .visionOCR,
                    pageCount: pageCount
                )
            }
        }
        
        // Stage 3: Fallback
        return ExtractionResult(
            text: nil,
            images: images,
            method: .rawImages,
            pageCount: pageCount
        )
    }
    
    /// Extracts content from a collection of images.
    ///
    /// - Parameter images: Input images (camera captures, screenshots, etc.)
    /// - Returns: An `ExtractionResult` describing the outcome.
    static func extract(from images: [UIImage]) async -> ExtractionResult {
        
        let ocrText = await extractWithVision(from: images)
        let averageChars = ocrText.count / max(images.count, 1)
        
        if averageChars >= minimumOCRCharsPerPage {
            return ExtractionResult(
                text: ocrText,
                images: nil,
                method: .visionOCR,
                pageCount: images.count
            )
        }
        
        return ExtractionResult(
            text: nil,
            images: images,
            method: .rawImages,
            pageCount: images.count
        )
    }
    
    // MARK: - Stage 1: PDFKit Extraction
    
    /// Attempts to extract embedded text using `PDFKit`.
    ///
    /// - Parameter url: The PDF file URL.
    /// - Returns: Cleaned text if available, otherwise `nil`.
    static func extractWithPDFKit(from url: URL) -> String? {
        let pages = extractPDFKitPages(from: url)
        guard pages.contains(where: { !$0.isEmpty }) else { return nil }
        return pages.joined(separator: pageSeparator)
    }

    /// Extracts one cleaned text payload for each PDF page using `PDFKit`.
    ///
    /// Empty pages are preserved as empty strings so page indices remain stable.
    static func extractPDFKitPages(from url: URL) -> [String] {
        guard let pdf = PDFDocument(url: url) else {
            return []
        }

        return (0..<pdf.pageCount).map { index -> String in
            guard let rawText = pdf.page(at: index)?.string else { return "" }

            let cleaned = rawText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return cleaned
        }
    }
    
    /// Computes a normalized quality score for PDFKit extraction.
    ///
    /// - Parameter url: The PDF file URL.
    /// - Returns: A value between 0.0 and 1.0.
    static func pdfKitQuality(for url: URL) -> Double {
        
        guard let text = extractWithPDFKit(from: url) else { return 0.0 }
        
        let pageCount = max(pdfPageCount(url: url), 1)
        let charsPerPage = Double(text.count) / Double(pageCount)
        
        switch charsPerPage {
        case 500...: return 1.0
        case 200...: return 0.8
        case 100...: return 0.5
        default:     return 0.1
        }
    }
    
    static func pdfPageCount(url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
    
    // MARK: - Stage 2: Vision OCR
    
    /// Performs OCR on a collection of images using Vision.
    static func extractWithVision(from images: [UIImage]) async -> String {
        let pages = await extractVisionTexts(from: images)
        return pages
            .filter { !$0.isEmpty }
            .joined(separator: pageSeparator)
    }

    /// Performs OCR on each image independently and preserves source order.
    static func extractVisionTexts(from images: [UIImage]) async -> [String] {

        var results: [String] = []

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let text = await ocrPage(cgImage: cgImage)
            results.append(text)
        }

        return results
    }

    /// Returns `true` when the OCR text density is good enough to drive the
    /// cheaper text-generation path without falling back to Vision requests.
    static func isUsableOCRText(_ texts: [String]) -> Bool {
        guard !texts.isEmpty else { return false }
        let totalCharacters = texts.reduce(0) { $0 + $1.count }
        let averageChars = totalCharacters / max(texts.count, 1)
        return averageChars >= minimumOCRCharsPerPage
    }
    
    private static func ocrPage(cgImage: CGImage) async -> String {
        
        await withCheckedContinuation { continuation in
            
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { observation -> String? in
                        guard let candidate = observation.topCandidates(1).first,
                              candidate.confidence > 0.3 else {
                            return nil
                        }
                        return candidate.string
                    }
                    .joined(separator: "\n") ?? ""
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ro-RO", "en-US", "fr-FR", "de-DE"]
            request.automaticallyDetectsLanguage = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }
    
    // MARK: - PDF Rendering

    /// Renders compact PDF page thumbnails for the source picker and preview UI.
    ///
    /// The output is intentionally small because previews are displayed inside
    /// narrow cards and lightweight modal previews.
    static func renderPDFPreviewThumbnails(
        from url: URL,
        maxDimension: CGFloat = 220
    ) async -> [UIImage] {

        guard let pdf = PDFDocument(url: url) else { return [] }

        return await withTaskGroup(of: (Int, UIImage?).self) { group in

            for index in 0..<pdf.pageCount {
                group.addTask {
                    guard let page = pdf.page(at: index) else {
                        return (index, nil)
                    }
                    return (index, renderPreviewThumbnail(for: page, maxDimension: maxDimension))
                }
            }

            var rendered: [(Int, UIImage)] = []

            for await (index, image) in group {
                if let image = image {
                    rendered.append((index, image))
                }
            }

            return rendered
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }
    
    /// Renders PDF pages into `UIImage` representations.
    static func renderPDFPages(from url: URL, dpi: CGFloat = 150) async -> [UIImage] {
        
        guard let pdf = PDFDocument(url: url) else { return [] }
        
        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            
            for index in 0..<pdf.pageCount {
                group.addTask {
                    guard let page = pdf.page(at: index) else {
                        return (index, nil)
                    }
                    return (index, renderPage(page, dpi: dpi))
                }
            }
            
            var rendered: [(Int, UIImage)] = []
            
            for await (index, image) in group {
                if let image = image {
                    rendered.append((index, image))
                }
            }
            
            return rendered
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }
    
    private static func renderPage(_ page: PDFPage, dpi: CGFloat) -> UIImage? {
        
        let scale = dpi / 72.0
        let pageRect = page.bounds(for: .mediaBox)
        let size = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private static func renderPreviewThumbnail(
        for page: PDFPage,
        maxDimension: CGFloat
    ) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale = min(maxDimension / pageRect.width, maxDimension / pageRect.height)
        let targetSize = CGSize(
            width: max(pageRect.width * scale, 1),
            height: max(pageRect.height * scale, 1)
        )

        return page.thumbnail(of: targetSize, for: .mediaBox)
    }
}

// MARK: - PDFKitDiagnostic

/// Utility tool for evaluating PDFKit extraction quality.
///
/// Intended for debugging and internal diagnostics.
struct PDFKitDiagnostic {
    
    static func run(for url: URL) async {
        
        print("\n===== PDFKit Diagnostic =====")
        print("File: \(url.lastPathComponent)")
        
        guard let pdf = PDFDocument(url: url) else {
            print("Could not open PDF.")
            return
        }
        
        let pageCount = pdf.pageCount
        print("Pages: \(pageCount)")
        
        guard let fullText = pdf.string else {
            print("No embedded text detected. Likely scanned PDF.")
            print("Recommendation: Vision OCR or GPT Vision.")
            return
        }
        
        let totalChars = fullText.count
        let avgPerPage = totalChars / max(pageCount, 1)
        let quality = DocumentTextExtractor.pdfKitQuality(for: url)
        
        print("Total characters: \(totalChars)")
        print("Average per page: \(avgPerPage)")
        print("Quality score: \(Int(quality * 100))%")
        
        for index in 0..<min(3, pageCount) {
            if let page = pdf.page(at: index),
               let pageText = page.string {
                
                let preview = String(pageText.prefix(150))
                    .replacingOccurrences(of: "\n", with: " ")
                
                print("Page \(index + 1) preview: \"\(preview)...\"")
            }
        }
        
        switch quality {
        case 0.8...:
            print("Excellent quality — use PDFKit directly.")
        case 0.5...:
            print("Medium quality — PDFKit usable, GPT correction recommended.")
        default:
            print("Poor quality — switch to Vision OCR.")
        }
        
        print("=============================\n")
    }
}
