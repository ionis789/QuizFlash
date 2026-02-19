//
//  TextExtractionService.swift
//  QuizFlash
//
//  Created by Ion Socol on 19.02.2026.
//


import Foundation
import UIKit
import Vision
import PDFKit

// MARK: - Extraction Errors
enum TextExtractionError: LocalizedError {
    case invalidImage
    case invalidPDF
    case pdfIsEncrypted
    case extractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be processed."
        case .invalidPDF:
            return "The selected PDF file is invalid or corrupted."
        case .pdfIsEncrypted:
            return "Cannot extract text from a password-protected PDF."
        case .extractionFailed(let reason):
            return "Failed to extract text: \(reason)"
        }
    }
}

// MARK: - Text Extraction Service
/// An isolated actor responsible for heavy document and image parsing.
/// Keeps CPU-intensive OCR and PDF operations completely off the Main Thread.
actor TextExtractionService {
    
    // MARK: - Public API
    
    /// Extracts text from a given UIImage using Apple's Vision framework.
    /// - Parameter image: The image containing text.
    /// - Returns: A string containing all recognized text.
    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw TextExtractionError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: TextExtractionError.extractionFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Combine all top candidates into a single string
                let recognizedText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: recognizedText)
            }
            
            // Prioritize accuracy over speed since this text goes to an AI for flashcard generation
            request.recognitionLevel = .accurate
            // Enable language correction for better contextual OCR
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: TextExtractionError.extractionFailed(error.localizedDescription))
            }
        }
    }
    
    /// Extracts text from a PDF file located at the specified URL.
    /// - Parameter url: The local file URL of the PDF.
    /// - Returns: A string containing all text parsed from the PDF pages.
    func extractText(fromPDFAt url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw TextExtractionError.invalidPDF
        }
        
        if document.isEncrypted {
            throw TextExtractionError.pdfIsEncrypted
        }
        
        var extractedText = ""
        let pageCount = document.pageCount
        
        // Iterate through all pages and append text
        for i in 0..<pageCount {
            guard let page = document.page(at: i),
                  let pageText = page.string else {
                continue
            }
            
            extractedText += pageText + "\n\n"
        }
        
        let cleanedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanedText.isEmpty {
            throw TextExtractionError.extractionFailed("No readable text found in the PDF. It might be an image-based PDF.")
        }
        
        return cleanedText
    }
}
