//
//  Documenttextextractor.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.02.2026.
//
import Foundation
import UIKit
import PDFKit
import Vision

// =============================================================================
// MARK: - ExtractionResult
// Ce a returnat pipeline-ul și pe ce nivel a reușit.
// Folosit de UI ca să afișeze progres și de Service ca să aleagă prompt-ul corect.
// =============================================================================

enum ExtractionMethod {
    case pdfKit          // Gratuit, instant — text embedded în PDF
    case visionOCR       // Gratuit, pe device — PDF scanat / imagini
    case rawImages       // Plătit, cloud — fallback final cu imaginile originale
}

struct ExtractionResult {
    let text: String?           // nil doar dacă method == .rawImages
    let images: [UIImage]?      // nil dacă method != .rawImages
    let method: ExtractionMethod
    let pageCount: Int

    var isTextBased: Bool { method == .pdfKit || method == .visionOCR }
    var needsOCRCorrection: Bool { method == .visionOCR }
}

// =============================================================================
// MARK: - DocumentTextExtractor
//
// Pipeline cu 3 niveluri pentru extragerea textului din documente:
//
//   Nivel 1 — PDFKit:    PDF cu text embedded → string instant, gratuit
//   Nivel 2 — Vision:    PDF scanat / imagini → OCR pe device, gratuit
//   Nivel 3 — Fallback:  Returnează imaginile brute pentru GPT Vision API
//
// Folosire:
//   let result = await DocumentTextExtractor.extract(from: pdfURL)
//   let result = await DocumentTextExtractor.extract(from: images)
// =============================================================================

actor DocumentTextExtractor {

    // MARK: - Thresholds
    // Câte caractere minime considerăm că PDFKit a extras cu succes
    private static let minimumPDFTextLength = 100
    // Câte caractere minime per pagină considerăm OCR decent
    private static let minimumOCRCharsPerPage = 30

    // -------------------------------------------------------------------------
    // Entry point 1: PDF (URL)
    // -------------------------------------------------------------------------
    static func extract(from pdfURL: URL) async -> ExtractionResult {
        let pageCount = await pdfPageCount(url: pdfURL)

        // Nivel 1: PDFKit
        if let text = extractWithPDFKit(from: pdfURL),
           text.count >= minimumPDFTextLength {
            print("✅ [Extractor] PDFKit: \(text.count) chars, \(pageCount) pages")
            return ExtractionResult(text: text, images: nil, method: .pdfKit, pageCount: pageCount)
        }

        print("⚠️ [Extractor] PDFKit insuficient, trec la Vision OCR...")

        // Nivel 2: Vision OCR pe imaginile PDF
        let images = await renderPDFPages(from: pdfURL)
        if !images.isEmpty {
            let ocrText = await extractWithVision(from: images)
            let avgChars = ocrText.count / max(images.count, 1)

            if avgChars >= minimumOCRCharsPerPage {
                print("✅ [Extractor] Vision OCR: \(ocrText.count) chars, avg \(avgChars)/pag")
                return ExtractionResult(text: ocrText, images: nil, method: .visionOCR, pageCount: pageCount)
            }
        }

        // Nivel 3: Fallback — trimitem imaginile la GPT Vision
        print("⚠️ [Extractor] OCR slab, fallback la GPT Vision cu \(images.count) imagini")
        return ExtractionResult(text: nil, images: images, method: .rawImages, pageCount: pageCount)
    }

    // -------------------------------------------------------------------------
    // Entry point 2: Imagini directe (foto din cameră, screenshot etc.)
    // -------------------------------------------------------------------------
    static func extract(from images: [UIImage]) async -> ExtractionResult {
        // Nivel 2: Vision OCR
        let ocrText = await extractWithVision(from: images)
        let avgChars = ocrText.count / max(images.count, 1)

        if avgChars >= minimumOCRCharsPerPage {
            print("✅ [Extractor] Vision OCR pe imagini: \(ocrText.count) chars")
            return ExtractionResult(text: ocrText, images: nil, method: .visionOCR, pageCount: images.count)
        }

        // Nivel 3: Fallback Vision API
        print("⚠️ [Extractor] OCR pe imagini slab, fallback GPT Vision")
        return ExtractionResult(text: nil, images: images, method: .rawImages, pageCount: images.count)
    }

    // =========================================================================
    // MARK: - Nivel 1: PDFKit
    // =========================================================================

    static func extractWithPDFKit(from url: URL) -> String? {
        guard let pdf = PDFDocument(url: url) else { return nil }
        guard let rawText = pdf.string else { return nil }

        let cleaned = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Elimină spații multiple și caractere de control
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Returnează calitatea extracției PDFKit: 0.0 (eșec) → 1.0 (perfect)
    /// Util pentru debugging și pentru UI care arată utilizatorului ce metodă s-a folosit.
    static func pdfKitQuality(for url: URL) -> Double {
        guard let text = extractWithPDFKit(from: url) else { return 0.0 }
        let pageCount = max(pdfPageCount(url: url), 1)
        let charsPerPage = Double(text.count) / Double(pageCount)

        switch charsPerPage {
        case 500...:  return 1.0   // Excelent
        case 200...:  return 0.8   // Bun
        case 100...:  return 0.5   // Acceptabil
        default:      return 0.1   // Slab
        }
    }

    private static func pdfPageCount(url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    // =========================================================================
    // MARK: - Nivel 2: Vision OCR
    // =========================================================================

    static func extractWithVision(from images: [UIImage]) async -> String {
        var results: [String] = []

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let pageText = await ocrPage(cgImage: cgImage)
            if !pageText.isEmpty {
                results.append(pageText)
            }
        }

        return results.joined(separator: "\n\n--- Pagina următoare ---\n\n")
    }

    private static func ocrPage(cgImage: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil else {
                    continuation.resume(returning: "")
                    return
                }

                let text = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { obs -> String? in
                        guard let candidate = obs.topCandidates(1).first,
                              candidate.confidence > 0.3 else { return nil }
                        return candidate.string
                    }
                    .joined(separator: "\n") ?? ""

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Adaugă toate limbile relevante pentru utilizatorii tăi
            request.recognitionLanguages = ["ro-RO", "en-US", "fr-FR", "de-DE"]
            // Detectează automat limba dacă lista de mai sus nu acoperă
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // =========================================================================
    // MARK: - Render PDF pages → UIImage
    // =========================================================================

    static func renderPDFPages(from url: URL, dpi: CGFloat = 150) async -> [UIImage] {
        guard let pdf = PDFDocument(url: url) else { return [] }

        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in 0..<pdf.pageCount {
                group.addTask {
                    guard let page = pdf.page(at: i) else { return (i, nil) }
                    let image = renderPage(page, dpi: dpi)
                    return (i, image)
                }
            }

            var results: [(Int, UIImage)] = []
            for await (index, image) in group {
                if let img = image { results.append((index, img)) }
            }

            // Sortăm după index ca să menținem ordinea paginilor
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private static func renderPage(_ page: PDFPage, dpi: CGFloat) -> UIImage? {
        let scale = dpi / 72.0
        let pageRect = page.bounds(for: .mediaBox)
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}

// =============================================================================
// MARK: - PDFKit Quality Checker (pentru debugging / UI feedback)
//
// Apelează asta când vrei să testezi cât de bine PDFKit citește un PDF specific.
// Afișează în consolă un raport detaliat.
// =============================================================================

struct PDFKitDiagnostic {

    static func run(for url: URL) async {
        print("\n🔍 ===== PDFKit Diagnostic =====")
        print("📄 Fișier: \(url.lastPathComponent)")

        guard let pdf = PDFDocument(url: url) else {
            print("❌ Nu am putut deschide PDF-ul")
            return
        }

        let pageCount = pdf.pageCount
        print("📑 Pagini: \(pageCount)")

        guard let fullText = pdf.string else {
            print("❌ PDFKit nu a extras niciun text — PDF probabil scanat")
            print("✅ Recomandare: Vision OCR sau GPT Vision")
            return
        }

        let totalChars = fullText.count
        let avgPerPage = totalChars / max(pageCount, 1)
        let quality = DocumentTextExtractor.pdfKitQuality(for: url)

        print("📊 Total caractere: \(totalChars)")
        print("📊 Medie / pagină: \(avgPerPage)")
        print("📊 Scor calitate: \(Int(quality * 100))%")

        // Primele 3 pagini — preview
        for i in 0..<min(3, pageCount) {
            if let page = pdf.page(at: i), let pageText = page.string {
                let preview = String(pageText.prefix(150))
                    .replacingOccurrences(of: "\n", with: " ")
                print("📄 Pagina \(i+1) preview: \"\(preview)...\"")
            }
        }

        switch quality {
        case 0.8...: print("✅ Calitate EXCELENTĂ — folosește PDFKit direct")
        case 0.5...: print("⚠️ Calitate MEDIE — PDFKit funcționează, dar GPT va trebui să corecteze")
        default:     print("❌ Calitate SLABĂ — treci la Vision OCR")
        }

        print("================================\n")
    }
}
