//
//  SearchEngine.swift
//  QuizFlash
//

import Foundation
import SwiftData

// MARK: - Search Engine
/// A decoupled actor that performs heavy string matching on a background thread.
/// By receiving simple, Sendable payloads, it guarantees we are searching the latest in-memory data
/// without waiting for SwiftData to sync contexts to disk.
actor SearchEngine {
    
    /// Performs a tokenized, deep, case-insensitive, and diacritic-insensitive search across the provided payloads.
    func performSearch(query: String, in payloads: [DeckSearchPayload]) -> [DeckSearchResultItem] {
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        
        var results: [DeckSearchResultItem] = []
        let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        
        for deck in payloads {
            var matchedCards: [MatchedCardInfo] = []
            
            // Check if ALL tokens are present in the deck title
            let titleMatches = tokens.allSatisfy { token in
                deck.title.range(of: token, options: searchOptions) != nil
            }
            
            for card in deck.cards {
                let fullText = card.frontText + " \n " + card.backText
                
                // Card is a match ONLY if all tokens exist somewhere on the card
                let matchesAnywhere = tokens.allSatisfy { token in
                    fullText.range(of: token, options: searchOptions) != nil
                }
                
                if matchesAnywhere {
                    let matchesFront = tokens.allSatisfy { card.frontText.range(of: $0, options: searchOptions) != nil }
                    let matchesBack = tokens.allSatisfy { card.backText.range(of: $0, options: searchOptions) != nil }
                    
                    let side: CardSideMatch
                    if matchesFront && matchesBack { side = .both }
                    else if matchesFront { side = .front }
                    else if matchesBack { side = .back }
                    else { side = .both } // Tokens scattered across both sides
                    
                    let snippetSource = matchesFront ? card.frontText : (matchesBack ? card.backText : fullText)
                    let snippet = extractMultiTokenSnippet(from: snippetSource, tokens: tokens, options: searchOptions)
                    
                    matchedCards.append(MatchedCardInfo(id: card.id, snippet: snippet, matchSide: side))
                }
            }
            
            if titleMatches || !matchedCards.isEmpty {
                results.append(DeckSearchResultItem(
                    id: deck.id,
                    deckTitle: deck.title,
                    deckIcon: deck.icon,
                    deckColorHex: deck.colorHex,
                    titleMatches: titleMatches,
                    matchedCards: matchedCards
                ))
            }
        }
        
        return results.sorted { a, b in
            if a.titleMatches && !b.titleMatches { return true }
            if !a.titleMatches && b.titleMatches { return false }
            return a.matchedCards.count > b.matchedCards.count
        }
    }
    
    // MARK: - Snippet Extraction Logic
    private func extractMultiTokenSnippet(from text: String, tokens: [String], options: String.CompareOptions, windowSize: Int = 30) -> String {
        let cleanText = text.replacingOccurrences(of: "\n", with: " ")
        var earliestRange: Range<String.Index>? = nil
        
        for token in tokens {
            if let range = cleanText.range(of: token, options: options) {
                if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                    earliestRange = range
                }
            }
        }
        
        guard let range = earliestRange else {
            return String(cleanText.prefix(windowSize * 2))
        }
        
        let startDistance = cleanText.distance(from: cleanText.startIndex, to: range.lowerBound)
        let safeStartOffset = max(0, startDistance - windowSize)
        let snippetStart = cleanText.index(cleanText.startIndex, offsetBy: safeStartOffset)
        
        let endDistance = cleanText.distance(from: range.upperBound, to: cleanText.endIndex)
        let safeEndOffset = min(endDistance, windowSize + 30)
        let snippetEnd = cleanText.index(range.upperBound, offsetBy: safeEndOffset)
        
        var snippet = String(cleanText[snippetStart..<snippetEnd])
        
        if snippetStart > cleanText.startIndex { snippet = "..." + snippet }
        if snippetEnd < cleanText.endIndex { snippet += "..." }
        
        return snippet
    }
}
