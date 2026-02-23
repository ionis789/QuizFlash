//
//  AIGenerationState.swift
//  QuizFlash
//

import Foundation

// MARK: - AI Generation State
public enum AIGenerationState: Equatable {
    case idle
    case analyzingDocument
    case extractingText
    case generatingCards(progress: Double, foundCount: Int)
    case error(String)

    public static func == (lhs: AIGenerationState, rhs: AIGenerationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.analyzingDocument, .analyzingDocument),
             (.extractingText, .extractingText):
            return true
        case (.generatingCards(let lp, let lc), .generatingCards(let rp, let rc)):
            return lp == rp && lc == rc
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - PDF Quality Info
struct PDFAnalysisInfo {
    let quality: Double
    let pageCount: Int
    let extractedChars: Int

    var recommendation: ExtractionMode {
        quality >= 0.8 ? .fast : .quality
    }

    var qualityLabel: String {
        switch quality {
        case 0.8...: return "Text detected perfectly"
        case 0.5...: return "Text detectat partial"
        case 0.1...: return "This PDF cannnot be used, try another one"
        default: return "This PDF cannnot be used, try another one"
        }
    }

    var qualityIcon: String {
        switch quality {
        case 0.5...: return "checkmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var isGoodForFast: Bool { quality >= 0.8 }
}

enum ExtractionMode: String {
    case fast = "fast"
    case quality = "quality(Premium)"
}

// MARK: - AI Flashcard Model
public struct AIFlashcard: Identifiable, Codable {
    public let id: UUID
    public let question: String
    public let answer: String

    public init(id: UUID = UUID(), question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

// MARK: - AI Generation Response
public struct AIGenerationResponse: Codable {
    public let flashcards: [AIFlashcard]
}
