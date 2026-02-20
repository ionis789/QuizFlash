//
//  AIGenerationState.swift
//  QuizFlash
//

import Foundation

// MARK: - AI Generation State
public enum AIGenerationState: Equatable {
    case idle
    case extractingText
    // Am adăugat progresul (0.0 - 1.0) și numărul de carduri generate în timp real
    case generatingCards(progress: Double, foundCount: Int)
    case error(String)

    public static func == (lhs: AIGenerationState, rhs: AIGenerationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.extractingText, .extractingText):
            return true
        case (.generatingCards(let lp, let lc), .generatingCards(let rp, let rc)):
            return lp == rp && lc == rc
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
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
