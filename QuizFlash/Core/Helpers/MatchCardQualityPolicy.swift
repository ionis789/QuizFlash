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
    let profile: MatchCardGameplayProfile
    let promptWordCount: Int
    let answerWordCount: Int
    let totalCharacterCount: Int
    let punctuationCount: Int
    let containsLineBreaks: Bool
    let qualityIssues: [String]

    /// `true` when the pair is compact enough for dedicated Match gameplay.
    var isCompact: Bool {
        !containsLineBreaks
            && prompt.count <= MatchCardQualityPolicy.maxPromptCharacters(for: profile)
            && answer.count <= MatchCardQualityPolicy.maxAnswerCharacters(for: profile)
            && promptWordCount <= MatchCardQualityPolicy.maxPromptWords(for: profile)
            && answerWordCount <= MatchCardQualityPolicy.maxAnswerWords(for: profile)
            && totalCharacterCount <= MatchCardQualityPolicy.maxTotalCharacters(for: profile)
            && punctuationCount <= MatchCardQualityPolicy.maxPunctuationCharacters(for: profile)
    }

    var isStrongExample: Bool {
        isCompact && qualityIssues.isEmpty
    }

    /// Stable prompt-like hint used to avoid regenerating the same weak pair.
    var retryHint: String {
        if qualityIssues.isEmpty {
            return "\(prompt) → \(answer)"
        }
        return "\(prompt) → \(answer) [issues: \(qualityIssues.joined(separator: ", "))]"
    }
}

nonisolated enum MatchCardGameplayProfile: Equatable, Sendable {
    case plain
    case symbolic
    case code
}

/// Shared compactness gate used by AI generation, AI conversion, and editor diagnostics.
nonisolated enum MatchCardQualityPolicy {
    nonisolated private static let punctuationCharacters = CharacterSet(charactersIn: ".,;:!?")
    nonisolated private static let symbolicCharacters = CharacterSet(charactersIn: "\\/*+-=<>()[]{}.,;:`'\"|&!?_^%@#$~")

    nonisolated static func maxPromptCharacters(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 72
        case .symbolic: return 84
        case .code: return 96
        }
    }

    nonisolated static func maxAnswerCharacters(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 56
        case .symbolic: return 80
        case .code: return 88
        }
    }

    nonisolated static func maxPromptWords(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 12
        case .symbolic: return 14
        case .code: return 15
        }
    }

    nonisolated static func maxAnswerWords(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 10
        case .symbolic: return 13
        case .code: return 14
        }
    }

    nonisolated static func maxTotalCharacters(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 110
        case .symbolic: return 140
        case .code: return 156
        }
    }

    nonisolated static func maxPunctuationCharacters(for profile: MatchCardGameplayProfile) -> Int {
        switch profile {
        case .plain: return 2
        case .symbolic: return 8
        case .code: return 14
        }
    }

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
        let profile = gameplayProfile(prompt: normalizedPrompt, answer: normalizedAnswer)
        let promptWordCount = normalizedPrompt.split(whereSeparator: \.isWhitespace).count
        let answerWordCount = normalizedAnswer.split(whereSeparator: \.isWhitespace).count
        let totalCharacterCount = normalizedPrompt.count + normalizedAnswer.count
        let punctuationCount = (normalizedPrompt + normalizedAnswer).unicodeScalars.filter {
            punctuationCharacters.contains($0)
        }.count
        let containsLineBreaks = normalizedPrompt.contains("\n") || normalizedAnswer.contains("\n")
        let qualityIssues = heuristicQualityIssues(
            prompt: normalizedPrompt,
            answer: normalizedAnswer,
            promptWordCount: promptWordCount,
            answerWordCount: answerWordCount,
            punctuationCount: punctuationCount
        )

        return MatchCardQualityEvaluation(
            prompt: normalizedPrompt,
            answer: normalizedAnswer,
            profile: profile,
            promptWordCount: promptWordCount,
            answerWordCount: answerWordCount,
            totalCharacterCount: totalCharacterCount,
            punctuationCount: punctuationCount,
            containsLineBreaks: containsLineBreaks,
            qualityIssues: qualityIssues
        )
    }

    nonisolated private static func heuristicQualityIssues(
        prompt: String,
        answer: String,
        promptWordCount: Int,
        answerWordCount: Int,
        punctuationCount: Int
    ) -> [String] {
        var issues: [String] = []
        let lowercasedPrompt = prompt.lowercased()
        let lowercasedAnswer = answer.lowercased()
        let profile = gameplayProfile(prompt: prompt, answer: answer)
        let isTechnicalProfile = profile == .code || profile == .symbolic
        let bucketPromptSignals = [
            "examples of", "example of", "benefits of", "advantages of", "types of", "kinds of",
            "categories of", "properties of", "characteristics of", "features of"
        ]
        let bucketAnswerSignals = [
            "examples of", "example of", "must be handled", "do not need to be handled",
            "runtimeexceptions", "runtime exceptions", "errors)", "errors (", "types include",
            "benefits include"
        ]

        if prompt.contains("?") {
            issues.append("question_style_prompt")
        }

        if !isTechnicalProfile && promptWordCount > 6 {
            issues.append("broad_prompt")
        }

        if bucketPromptSignals.contains(where: { lowercasedPrompt.contains($0) }) {
            issues.append("bucket_prompt")
        }

        let answerWordLimit: Int
        switch profile {
        case .plain:
            answerWordLimit = 8
        case .symbolic:
            answerWordLimit = 10
        case .code:
            answerWordLimit = 12
        }

        if answerWordCount > answerWordLimit {
            issues.append("long_answer")
        }

        if !isTechnicalProfile && (answer.contains(",") || answer.contains(";") || answer.contains(":") || punctuationCount > 1) {
            issues.append("list_like_answer")
        }

        if bucketAnswerSignals.contains(where: { lowercasedAnswer.contains($0) }) {
            issues.append("bucket_answer")
        }

        if !isTechnicalProfile && (
            lowercasedAnswer.contains("by which")
            || lowercasedAnswer.contains("the process by")
            || lowercasedAnswer.contains("which ")
            || lowercasedAnswer.contains(" reflects")
            || lowercasedAnswer.contains(" highlights")
        ) {
            issues.append("explanatory_answer")
        }

        if lowercasedPrompt.contains("characteristics of")
            || lowercasedPrompt.contains("elements of")
            || lowercasedPrompt.contains("functions of")
            || lowercasedPrompt.contains("stages of")
            || lowercasedPrompt.contains("benefits of")
            || lowercasedPrompt.contains("advantages of")
            || lowercasedPrompt.contains("types of")
            || lowercasedPrompt.contains("categories of")
        {
            issues.append("multi_clause_concept")
        }

        return Array(Set(issues)).sorted()
    }

    nonisolated private static func gameplayProfile(
        prompt: String,
        answer: String
    ) -> MatchCardGameplayProfile {
        let combined = "\(prompt) \(answer)"
        let lowercased = combined.lowercased()

        let codeSignals = [
            "class ", "interface ", "throws", "throw ", "catch", "try", "finally",
            "public ", "private ", "protected ", "static ", "void ", "return ",
            "new ", "null", "extends", "implements", "autocloseable", "exception",
            "[]", "()", "{}", ".java", "main(", "read(", "close("
        ]

        let symbolicSignals = [
            "\\", "->", "=>", "==", "!=", "<=", ">=", "::", "<>", "∈", "∀", "∑", "λ", "φ"
        ]

        let codeScore = codeSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) || combined.contains(signal) { score += 1 }
        }

        let symbolicScore = symbolicSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) || combined.contains(signal) { score += 1 }
        } + combined.unicodeScalars.filter { symbolicCharacters.contains($0) }.count / 8

        if codeScore >= 2 {
            return .code
        }

        if symbolicScore >= 2 {
            return .symbolic
        }

        return .plain
    }
}
