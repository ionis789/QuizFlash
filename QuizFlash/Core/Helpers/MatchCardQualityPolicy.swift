//
//  MatchCardQualityPolicy.swift
//  QuizFlash
//
//  Shared compactness rules for dedicated Match cards.
//

import Foundation

// MARK: - Match Card Quality Policy

/// Normalized quality verdict for one dedicated Match prompt/answer pair.
nonisolated struct MatchCardQualityEvaluation: Equatable, Sendable {
    let prompt: String
    let answer: String
    let promptWordCount: Int
    let answerWordCount: Int
    let totalCharacterCount: Int
    let punctuationCount: Int
    let containsLineBreaks: Bool

    /// `true` when the pair is compact enough for dedicated Match gameplay.
    var isCompact: Bool {
        !containsLineBreaks
            && prompt.count <= MatchCardQualityPolicy.maxPromptCharacters
            && answer.count <= MatchCardQualityPolicy.maxAnswerCharacters
            && promptWordCount <= MatchCardQualityPolicy.maxPromptWords
            && answerWordCount <= MatchCardQualityPolicy.maxAnswerWords
            && totalCharacterCount <= MatchCardQualityPolicy.maxTotalCharacters
            && punctuationCount <= MatchCardQualityPolicy.maxPunctuationCharacters
    }

    /// Stable prompt-like hint used to avoid regenerating the same weak pair.
    var retryHint: String {
        "\(prompt) → \(answer)"
    }
}

/// Shared compactness gate used by AI generation, AI conversion, and editor diagnostics.
nonisolated enum MatchCardQualityPolicy {
    static let maxPromptCharacters = 72
    static let maxAnswerCharacters = 56
    static let maxPromptWords = 12
    static let maxAnswerWords = 10
    static let maxTotalCharacters = 110
    static let maxPunctuationCharacters = 2

    nonisolated private static let punctuationCharacters = CharacterSet(charactersIn: ".,;:!?")

    /// Normalizes one Match field into a single compact line.
    nonisolated static func normalizedText(_ text: String) -> String {
        AIZoneParser.sanitizeLatex(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Evaluates whether a dedicated Match pair is compact enough for gameplay.
    nonisolated static func evaluate(
        prompt: String,
        answer: String
    ) -> MatchCardQualityEvaluation {
        let normalizedPrompt = normalizedText(prompt)
        let normalizedAnswer = normalizedText(answer)

        return MatchCardQualityEvaluation(
            prompt: normalizedPrompt,
            answer: normalizedAnswer,
            promptWordCount: normalizedPrompt.split(whereSeparator: \.isWhitespace).count,
            answerWordCount: normalizedAnswer.split(whereSeparator: \.isWhitespace).count,
            totalCharacterCount: normalizedPrompt.count + normalizedAnswer.count,
            punctuationCount: (normalizedPrompt + normalizedAnswer).unicodeScalars.filter {
                punctuationCharacters.contains($0)
            }.count,
            containsLineBreaks: normalizedPrompt.contains("\n") || normalizedAnswer.contains("\n")
        )
    }
}
