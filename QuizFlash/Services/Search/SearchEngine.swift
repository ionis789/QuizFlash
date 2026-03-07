//
//  SearchEngine.swift
//  QuizFlash
//

import Foundation
import SwiftData

actor SearchEngine {

    nonisolated func performSearchStream(
        query: String,
        in payloads: [DeckSearchPayload]
    ) -> AsyncStream<[DeckSearchResultItem]> {

        AsyncStream { continuation in
            let task = Task {
                let tokens = query
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }

                guard !tokens.isEmpty else {
                    continuation.finish()
                    return
                }

                var results: [DeckSearchResultItem] = []
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                var matchedDeckCount = 0

                let cap = await MainActor.run { SearchEngineConfig.previewCardCap }
                let yieldDecks = await MainActor.run { SearchEngineConfig.yieldEveryNDecks }

                for deck in payloads {
                    if Task.isCancelled { break }

                    var previewCards: [MatchedCardInfo] = []
                    var totalMatched = 0
                    let titleMatches = tokens.allSatisfy {
                        deck.title.range(of: $0, options: options) != nil
                    }

                    for card in deck.cards {
                        var matchesFront    = true
                        var matchesBack     = true
                        var matchesCombined = true

                        for token in tokens {
                            let inFront = card.frontText.range(of: token, options: options) != nil
                            let inBack  = card.backText.range(of: token, options: options) != nil
                            if !inFront { matchesFront    = false }
                            if !inBack  { matchesBack     = false }
                            if !inFront && !inBack { matchesCombined = false; break }
                        }

                        guard matchesCombined else { continue }

                        totalMatched += 1

                        // Store full card info up to the cap.
                        // Beyond the cap we only count — no string allocation.
                        if previewCards.count < cap {
                            let side: CardSideMatch
                            if matchesFront && matchesBack { side = .both }
                            else if matchesFront           { side = .front }
                            else                           { side = .back }

                            let snippetSource = matchesFront ? card.frontText : card.backText
                            let snippet = Self.extractSnippet(
                                from: snippetSource, tokens: tokens, options: options
                            )
                            previewCards.append(
                                MatchedCardInfo(id: card.id, snippet: snippet, matchSide: side)
                            )
                        }
                    }

                    guard titleMatches || totalMatched > 0 else { continue }

                    results.append(DeckSearchResultItem(
                        id: deck.id,
                        deckTitle: deck.title,
                        deckIcon: deck.icon,
                        deckColorHex: deck.colorHex,
                        titleMatches: titleMatches,
                        matchedCards: previewCards,
                        totalMatchedCardsCount: totalMatched
                    ))

                    matchedDeckCount += 1

                    if matchedDeckCount == 1 ||
                       matchedDeckCount % yieldDecks == 0 {
                        continuation.yield(Self.sorted(results))
                        await Task.yield()
                    }
                }

                if !Task.isCancelled {
                    continuation.yield(Self.sorted(results))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    nonisolated private static func sorted(_ results: [DeckSearchResultItem]) -> [DeckSearchResultItem] {
        results.sorted { a, b in
            if a.titleMatches != b.titleMatches { return a.titleMatches }
            return a.totalMatchedCardsCount > b.totalMatchedCardsCount
        }
    }

    nonisolated private static func extractSnippet(
        from text: String,
        tokens: [String],
        options: String.CompareOptions,
        windowSize: Int = 40
    ) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        var earliest: Range<String.Index>?

        for token in tokens {
            if let r = clean.range(of: token, options: options) {
                if earliest == nil || r.lowerBound < earliest!.lowerBound { earliest = r }
            }
        }

        guard let range = earliest else { return String(clean.prefix(windowSize * 2)) }

        let startDist = clean.distance(from: clean.startIndex, to: range.lowerBound)
        let startOff  = max(0, startDist - windowSize)
        let start     = clean.index(clean.startIndex, offsetBy: startOff)

        let endDist   = clean.distance(from: range.upperBound, to: clean.endIndex)
        let endOff    = min(endDist, windowSize + 40)
        let end       = clean.index(range.upperBound, offsetBy: endOff)

        var snippet = String(clean[start..<end])
        if start > clean.startIndex { snippet = "…" + snippet }
        if end   < clean.endIndex   { snippet += "…" }
        return snippet
    }
}
