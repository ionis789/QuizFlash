//
//  AIGeneratedCardContentMapper.swift
//  QuizFlash
//
//  Shared bridge from AI response payloads into persisted mixed-card content.
//

import Foundation

// MARK: - AI Generated Card Mapping

/// Converts structured AI responses into canonical `DraftCardContent` values.
enum AIGeneratedCardContentMapper {

    /// Maps one AI-generated card into the heterogeneous draft payload used by
    /// the editor, persistence, and conversion flows.
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
        case .match(let content):
            let prompt = content.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = content.answer.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !prompt.isEmpty, !answer.isEmpty else {
                throw AIGeneratedCardContentMappingError.invalidMatchCard
            }

            return .match(
                MatchCardContent(
                    prompt: prompt,
                    answer: answer
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
        case .write(let content):
            let sourceText = content.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let omittedText = content.omittedText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sourceText.isEmpty, !omittedText.isEmpty else {
                throw AIGeneratedCardContentMappingError.invalidWriteCard
            }

            let sourceZone = ZoneModel.text(sourceText)
            let nsSource = sourceText as NSString
            let range = nsSource.range(of: omittedText)

            guard range.location != NSNotFound, range.length > 0 else {
                throw AIGeneratedCardContentMappingError.invalidWriteCard
            }

            return .write(
                WriteCardContent(
                    sourceZone: sourceZone,
                    blankSelection: WriteBlankSelection(
                        zoneID: sourceZone.id,
                        utf16Range: range.location..<(range.location + range.length),
                        omittedText: omittedText
                    )
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
    case invalidMatchCard
    case invalidQuizCard
    case invalidWriteCard

    var errorDescription: String? {
        switch self {
        case .invalidMatchCard:
            return "The AI returned a match card without a valid prompt and answer pair."
        case .invalidQuizCard:
            return "The AI returned a quiz card without valid choices and correct answers."
        case .invalidWriteCard:
            return "The AI returned a write card whose omitted text could not be anchored in the source text."
        }
    }
}
