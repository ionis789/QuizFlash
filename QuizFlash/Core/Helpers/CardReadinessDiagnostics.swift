//
//  CardReadinessDiagnostics.swift
//  QuizFlash
//
//  Shared authoring/readiness heuristics for match and write cards.
//

import Foundation
import SwiftUI

// MARK: - Card Readiness Diagnostics

/// The small set of readiness states surfaced in authoring and preview UI.
enum CardReadinessDiagnosticKind: String, CaseIterable, Identifiable, Sendable {
    case matchReady
    case matchWeak
    case writeMathHeavy

    var id: String { rawValue }

    /// Short label used by compact chips.
    var shortTitle: String {
        switch self {
        case .matchReady:
            return "Match-ready"
        case .matchWeak:
            return "Match-weak"
        case .writeMathHeavy:
            return "Write math-heavy"
        }
    }

    /// Plural-friendly label used by deck-level summaries.
    var summaryTitle: String {
        switch self {
        case .matchReady:
            return "match-ready"
        case .matchWeak:
            return "match-weak"
        case .writeMathHeavy:
            return "write math-heavy"
        }
    }

    /// Symbol used across readiness chips and preview callouts.
    var symbol: String {
        switch self {
        case .matchReady:
            return "checkmark.circle.fill"
        case .matchWeak:
            return "exclamationmark.triangle.fill"
        case .writeMathHeavy:
            return "function"
        }
    }

    /// Semantic tint aligned with readiness severity.
    var tint: Color {
        switch self {
        case .matchReady:
            return .green
        case .matchWeak:
            return .orange
        case .writeMathHeavy:
            return .teal
        }
    }
}

/// One card-level readiness note shown inline in preview and authoring surfaces.
struct CardReadinessDiagnostic: Identifiable, Equatable, Sendable {
    let kind: CardReadinessDiagnosticKind
    let detail: String
    let recommendedConversionTargetKind: CardKind?

    var id: String { "\(kind.rawValue)-\(detail)" }
}

/// One deck-level readiness aggregate chip.
struct DeckReadinessSummaryItem: Identifiable, Equatable, Sendable {
    let kind: CardReadinessDiagnosticKind
    let count: Int

    var id: String { kind.rawValue }
    var title: String { "\(count) \(kind.summaryTitle)" }
}

/// One readiness-driven conversion recommendation aggregated from card diagnostics.
struct DeckReadinessConversionRecommendation: Identifiable, Equatable, Sendable {
    let targetKind: CardKind
    let count: Int

    var id: CardKind { targetKind }
    var title: String {
        "Convert \(count) card\(count == 1 ? "" : "s") to \(targetKind.displayTitle)"
    }
    var detail: String {
        "Open AI conversion with only the cards flagged by readiness diagnostics."
    }
}

/// Aggregated readiness counts for one deck snapshot.
struct DeckReadinessSummary: Equatable, Sendable {
    let matchReadyCount: Int
    let matchWeakCount: Int
    let writeMathHeavyCount: Int
    let recommendedConversions: [DeckReadinessConversionRecommendation]

    var hasContent: Bool {
        matchReadyCount > 0 || matchWeakCount > 0 || writeMathHeavyCount > 0
    }

    var items: [DeckReadinessSummaryItem] {
        var results: [DeckReadinessSummaryItem] = []

        if matchReadyCount > 0 {
            results.append(.init(kind: .matchReady, count: matchReadyCount))
        }
        if matchWeakCount > 0 {
            results.append(.init(kind: .matchWeak, count: matchWeakCount))
        }
        if writeMathHeavyCount > 0 {
            results.append(.init(kind: .writeMathHeavy, count: writeMathHeavyCount))
        }

        return results
    }

    nonisolated static let empty = DeckReadinessSummary(
        matchReadyCount: 0,
        matchWeakCount: 0,
        writeMathHeavyCount: 0,
        recommendedConversions: []
    )
}

/// Shared heuristics used by editor and preview surfaces to assess card readiness.
enum CardReadinessDiagnostics {

    // MARK: - Card Level

    /// Builds readiness notes for a draft or persisted content payload.
    /// - Parameter content: The heterogeneous card payload to inspect.
    /// - Returns: Zero or more readiness notes that should be surfaced to the user.
    nonisolated static func diagnostics(for content: DraftCardContent) -> [CardReadinessDiagnostic] {
        switch content {
        case .flashcard(let content):
            let prompt = normalizedSingleLine(content.frontZone.previewText(maxLength: 240))
            let answer = normalizedSingleLine(content.backZone.previewText(maxLength: 240))
            return matchDiagnostic(prompt: prompt, answer: answer, isFallback: true).map { [$0] } ?? []
        case .match(let content):
            let prompt = normalizedSingleLine(content.prompt)
            let answer = normalizedSingleLine(content.answer)
            return matchDiagnostic(prompt: prompt, answer: answer, isFallback: false).map { [$0] } ?? []
        case .quiz:
            return []
        case .write(let content):
            let sourceText = WriteBlankTextHelper.normalizedSourceText(from: content.sourceZone)
            let answer = normalizedSingleLine(content.blankSelection.omittedText)
            guard !answer.isEmpty,
                  WriteBlankTextHelper.isFormulaHeavy(answer: answer, sourceText: sourceText) else {
                return []
            }

            return [
                CardReadinessDiagnostic(
                    kind: .writeMathHeavy,
                    detail: "The omitted answer is symbol-dense enough that assisted builder input will usually feel better than free text.",
                    recommendedConversionTargetKind: nil
                )
            ]
        }
    }

    /// Builds readiness notes for one persisted grid snapshot card.
    /// - Parameter card: The lightweight projected card info.
    /// - Returns: Zero or more readiness notes derived from preview-safe text.
    nonisolated static func diagnostics(for card: GridCardInfo) -> [CardReadinessDiagnostic] {
        switch card.kind {
        case .flashcard:
            return matchDiagnostic(
                prompt: normalizedSingleLine(card.frontText),
                answer: normalizedSingleLine(card.backText),
                isFallback: true
            ).map { [$0] } ?? []
        case .match:
            return matchDiagnostic(
                prompt: normalizedSingleLine(card.frontText),
                answer: normalizedSingleLine(card.backText),
                isFallback: false
            ).map { [$0] } ?? []
        case .quiz:
            return []
        case .write:
            guard !normalizedSingleLine(card.backText).isEmpty,
                  WriteBlankTextHelper.isFormulaHeavy(
                    answer: card.backText,
                    sourceText: card.frontText
                  ) else {
                return []
            }

            return [
                CardReadinessDiagnostic(
                    kind: .writeMathHeavy,
                    detail: "This write card looks formula-heavy and is a good candidate for assisted builder input.",
                    recommendedConversionTargetKind: nil
                )
            ]
        }
    }

    /// Builds readiness notes for one live persisted card when richer payload access is available.
    /// - Parameter card: The live card model currently being previewed.
    /// - Returns: Zero or more readiness notes.
    nonisolated static func diagnostics(for card: CardModel) -> [CardReadinessDiagnostic] {
        diagnostics(for: card.cardContent)
    }

    // MARK: - Deck Level

    /// Aggregates readiness counts for a draft deck state.
    /// - Parameter cards: The current draft cards.
    /// - Returns: A compact summary suitable for chip strips.
    nonisolated static func summary(for cards: [DraftCard]) -> DeckReadinessSummary {
        summary(for: cards.map(\.content))
    }

    /// Aggregates readiness counts for heterogeneous content payloads.
    /// - Parameter contents: The deck card payloads to inspect.
    /// - Returns: A compact summary suitable for chip strips.
    nonisolated static func summary(for contents: [DraftCardContent]) -> DeckReadinessSummary {
        let diagnostics = contents.flatMap(diagnostics(for:))
        return buildSummary(from: diagnostics)
    }

    /// Aggregates readiness counts for a persisted deck snapshot.
    /// - Parameter cards: The projected grid cards for the current deck.
    /// - Returns: A compact summary suitable for chip strips.
    nonisolated static func summary(for cards: [GridCardInfo]) -> DeckReadinessSummary {
        let diagnostics = cards.flatMap(diagnostics(for:))
        return buildSummary(from: diagnostics)
    }

    // MARK: - Private Helpers

    private nonisolated static func buildSummary(
        from diagnostics: [CardReadinessDiagnostic]
    ) -> DeckReadinessSummary {
        let conversionCounts = Dictionary(grouping: diagnostics.compactMap(\.recommendedConversionTargetKind)) {
            $0
        }.mapValues(\.count)
        let recommendedConversions = conversionCounts
            .map { targetKind, count in
                DeckReadinessConversionRecommendation(targetKind: targetKind, count: count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.targetKind.displayTitle < $1.targetKind.displayTitle
                }
                return $0.count > $1.count
            }

        return DeckReadinessSummary(
            matchReadyCount: diagnostics.filter { $0.kind == .matchReady }.count,
            matchWeakCount: diagnostics.filter { $0.kind == .matchWeak }.count,
            writeMathHeavyCount: diagnostics.filter { $0.kind == .writeMathHeavy }.count,
            recommendedConversions: recommendedConversions
        )
    }

    private nonisolated static func matchDiagnostic(
        prompt: String,
        answer: String,
        isFallback: Bool
    ) -> CardReadinessDiagnostic? {
        guard !prompt.isEmpty, !answer.isEmpty else { return nil }

        let promptWords = prompt.split(whereSeparator: \.isWhitespace).count
        let answerWords = answer.split(whereSeparator: \.isWhitespace).count
        let totalCharacters = prompt.count + answer.count
        let punctuationCharacters = CharacterSet(charactersIn: ".,;:!?")
        let punctuationCount = (prompt + answer).unicodeScalars.filter {
            punctuationCharacters.contains($0)
        }.count
        let containsLineBreaks = prompt.contains("\n") || answer.contains("\n")
        let isCompact = !containsLineBreaks
            && prompt.count <= 72
            && answer.count <= 56
            && promptWords <= 12
            && answerWords <= 10
            && totalCharacters <= 110
            && punctuationCount <= 2

        if isCompact {
            return CardReadinessDiagnostic(
                kind: .matchReady,
                detail: isFallback
                    ? "This prompt-answer pair is compact enough to survive the flashcard fallback used by Match."
                    : "This dedicated prompt-answer pair is compact enough for Match on smaller screens.",
                recommendedConversionTargetKind: isFallback ? .match : nil
            )
        }

        return CardReadinessDiagnostic(
            kind: .matchWeak,
            detail: isFallback
                ? "This fallback prompt-answer text is too verbose for Match. A dedicated match card would read more clearly."
                : "This match card is still too verbose for fast rounds. Tighten the prompt or answer.",
            recommendedConversionTargetKind: isFallback ? .match : nil
        )
    }

    private nonisolated static func normalizedSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
