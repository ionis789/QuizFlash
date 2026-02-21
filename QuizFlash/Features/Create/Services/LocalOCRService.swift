//
//  LocalOCRService.swift
//  QuizFlash
//
//  Created by Ion Socol on 20.02.2026.
//
//
import Vision
import PDFKit
import UIKit

public actor LocalOCRService {
    
    public init() {}
    
    /// Extrage textul din imagini folosind Apple Vision
    func extractText(from images: [UIImage]) async throws -> String {
        var fullText = ""
        
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            
            if let observations = request.results {
                let pageText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                fullText += pageText + "\n\n"
            }
        }
        
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extrage textul nativ dintr-un PDF (instant)
    func extractText(fromPDF url: URL) -> String {
        guard let pdf = PDFDocument(url: url) else { return "" }
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let text = page.string {
                fullText += text + "\n\n"
            }
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
