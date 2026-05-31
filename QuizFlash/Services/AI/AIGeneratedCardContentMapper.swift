//
//  AIGeneratedCardContentMapper.swift
//  QuizFlash
//
//  Shared bridge from AI response payloads into persisted mixed-card content.
//

import Foundation

// MARK: - AI Generated Card Mapping

/// Maps structured AI responses into canonical `DraftCardContent` values.
enum AIGeneratedCardContentMapper {

    /// Maps one AI-generated card into the heterogeneous draft payload used by
    /// the editor and persistence flows.
    /// - Parameter generatedCard: The structured AI card to project.
    /// - Returns: A validated `DraftCardContent` value ready for persistence.
    /// - Throws: ``AIGeneratedCardContentMappingError`` when the payload is invalid.
    nonisolated static func map(_ generatedCard: AIFlashcard) throws -> DraftCardContent {
        switch generatedCard.content {
        case .flashcard(let content):
            return .flashcard(
                FlashcardCardContent(
                    frontZone: aiZone(from: content.questionZones),
                    backZone: aiZone(from: content.answerZones),
                    frontType: .text,
                    backType: .text
                )
            )
        case .quiz(let content):
            let validCorrectIndexes = Set(content.correctIndexes)
            let choices = content.choices.enumerated().map { index, choice in
                QuizChoiceDraft(
                    contentZone: AIZoneParser.parse(text: choice),
                    isCorrect: validCorrectIndexes.contains(index)
                )
            }

            guard !choices.isEmpty, choices.contains(where: \.isCorrect) else {
                throw AIGeneratedCardContentMappingError.invalidQuizCard
            }

            let explanationZone: ZoneModel?
            if let explanationZones = content.explanationZones, !explanationZones.isEmpty {
                explanationZone = aiZone(from: explanationZones)
            } else {
                explanationZone = nil
            }

            return .quiz(
                QuizCardContent(
                    questionZone: aiZone(from: content.questionZones),
                    choices: choices,
                    explanationZone: explanationZone,
                    allowsMultipleCorrect: content.allowsMultipleCorrect
                )
            )
        }
    }

    private nonisolated static func aiZone(from strings: [String]) -> ZoneModel {
        let parsedZones = strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { AIZoneParser.parse(text: $0) }

        switch parsedZones.count {
        case 0:
            return .text()
        case 1:
            return parsedZones[0]
        default:
            return .container(direction: .vertical, children: parsedZones)
        }
    }
}

/// Validation failures returned when the AI payload cannot be turned into a
/// stable `DraftCardContent` value.
enum AIGeneratedCardContentMappingError: LocalizedError {
    case invalidQuizCard

    var errorDescription: String? {
        switch self {
        case .invalidQuizCard:
            return "The AI returned a quiz card without valid choices and correct answers."
        }
    }
}
