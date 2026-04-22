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

    private var locale: Locale { AppPreferences.persistedResolvedLocale }

    /// Short label used by compact chips.
    var shortTitle: String {
        switch self {
        case .matchReady:
            return AppLocalization.string("Match-ready", locale: locale)
        case .matchWeak:
            return AppLocalization.string("Match-weak", locale: locale)
        case .writeMathHeavy:
            return AppLocalization.string("Write math-heavy", locale: locale)
        }
    }

    /// Plural-friendly label used by deck-level summaries.
    var summaryTitle: String {
        switch self {
        case .matchReady:
            return AppLocalization.string("match-ready", locale: locale)
        case .matchWeak:
            return AppLocalization.string("match-weak", locale: locale)
        case .writeMathHeavy:
            return AppLocalization.string("write math-heavy", locale: locale)
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
        let locale = AppPreferences.persistedResolvedLocale
        let kindTitle = switch targetKind {
        case .flashcard: AppLocalization.string("Flashcard", locale: locale)
        case .match: AppLocalization.string("Match", locale: locale)
        case .quiz: AppLocalization.string("Quiz", locale: locale)
        case .write: AppLocalization.string("Write", locale: locale)
        }
        let format = AppLocalization.string(
            count == 1 ? "Convert %d card to %@" : "Convert %d cards to %@",
            locale: locale
        )
        return String(format: format, locale: locale, count, kindTitle)
    }
    var detail: String {
        AppLocalization.string(
            "Open AI conversion with only the cards flagged by readiness diagnostics.",
            locale: AppPreferences.persistedResolvedLocale
        )
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
        case .flashcard:
            return []
        case .match(let content):
            return matchDiagnostic(prompt: content.prompt, answer: content.answer).map { [$0] } ?? []
        case .quiz:
            return []
        case .write(let content):
            let sourceText = WriteBlankTextHelper.normalizedSourceText(from: content.sourceZone)
            let answer = MatchCardQualityPolicy.normalizedText(content.blankSelection.omittedText)
            guard !answer.isEmpty,
                  WriteBlankTextHelper.isFormulaHeavy(answer: answer, sourceText: sourceText) else {
                return []
            }

            return [
                CardReadinessDiagnostic(
                    kind: .writeMathHeavy,
                    detail: AppLocalization.string(
                        "The omitted answer is symbol-dense enough that assisted builder input will usually feel better than free text.",
                        locale: AppPreferences.persistedResolvedLocale
                    ),
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
            return []
        case .match:
            return matchDiagnostic(
                prompt: card.frontText,
                answer: card.backText
            ).map { [$0] } ?? []
        case .quiz:
            return []
        case .write:
            guard !MatchCardQualityPolicy.normalizedText(card.backText).isEmpty,
                  WriteBlankTextHelper.isFormulaHeavy(
                    answer: card.backText,
                    sourceText: card.frontText
                  ) else {
                return []
            }

            return [
                CardReadinessDiagnostic(
                    kind: .writeMathHeavy,
                    detail: AppLocalization.string(
                        "This write card looks formula-heavy and is a good candidate for assisted builder input.",
                        locale: AppPreferences.persistedResolvedLocale
                    ),
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

    /// Aggregates only the subset of diagnostics that should stay visible on
    /// deck-detail surfaces. Match readiness stays editor-only.
    nonisolated static func deckSurfaceSummary(for cards: [GridCardInfo]) -> DeckReadinessSummary {
        let diagnostics = cards
            .flatMap(diagnostics(for:))
            .filter { $0.kind == .writeMathHeavy }
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
        answer: String
    ) -> CardReadinessDiagnostic? {
        let evaluation = MatchCardQualityPolicy.evaluate(
            prompt: prompt,
            answer: answer
        )
        guard !evaluation.prompt.isEmpty, !evaluation.answer.isEmpty else { return nil }

        if evaluation.isCompact {
            return CardReadinessDiagnostic(
                kind: .matchReady,
                detail: AppLocalization.string(
                    "This dedicated prompt-answer pair is compact enough for Match on smaller screens.",
                    locale: AppPreferences.persistedResolvedLocale
                ),
                recommendedConversionTargetKind: nil
            )
        }

        return CardReadinessDiagnostic(
            kind: .matchWeak,
            detail: AppLocalization.string(
                "This match card is still too verbose for fast rounds. Tighten the prompt or answer.",
                locale: AppPreferences.persistedResolvedLocale
            ),
            recommendedConversionTargetKind: nil
        )
    }
}
