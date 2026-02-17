//
//  SearchEngine.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//
import Foundation
import SwiftData

// MARK: - Search Engine (Background Actor)
// A background ModelActor ensures that heavy string matching across thousands
// of records does not block the Main Thread and avoids SwiftData concurrency crashes.

@ModelActor
actor SearchEngine {
    
    /// Performs a case-insensitive search across all decks and cards.
    func performSearch(query: String) throws -> [DeckSearchResultItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        
        let lowerQuery = trimmedQuery.localizedLowercase
        
        // Fetch all decks. (Optimization: We fetch everything and filter in memory here
        // because SwiftData Predicates currently have limitations with complex relationship substring matching).
        let descriptor = FetchDescriptor<DeckModel>()
        let allDecks = try modelContext.fetch(descriptor)
        
        var results: [DeckSearchResultItem] = []
        
        for deck in allDecks {
            var matchedCards: [MatchedCardInfo] = []
            let titleMatches = deck.title.localizedLowercase.contains(lowerQuery)
            
            for card in deck.cards {
                let frontMatches = card.frontText.localizedLowercase.contains(lowerQuery)
                let backMatches = card.backText.localizedLowercase.contains(lowerQuery)
                
                if frontMatches || backMatches {
                    // Extract a readable snippet framing the matched text
                    let sourceText = frontMatches ? card.frontText : card.backText
                    let snippet = extractSnippet(from: sourceText, query: trimmedQuery)
                    
                    matchedCards.append(MatchedCardInfo(
                        id: card.id,
                        snippet: snippet
                    ))
                }
            }
            
            // Only add the deck to results if its title matches OR it has matching cards
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
        
        // Return results sorted by the number of matches, or title matches first
        return results.sorted { a, b in
            if a.titleMatches && !b.titleMatches { return true }
            if !a.titleMatches && b.titleMatches { return false }
            return a.matchedCards.count > b.matchedCards.count
        }
    }
    
    // MARK: - Snippet Extraction Logic
    
    /// Extracts a ~60 character window around the matched query to display in the UI.
    private func extractSnippet(from text: String, query: String, windowSize: Int = 30) -> String {
        let cleanText = text.replacingOccurrences(of: "\n", with: " ")
        let lowerText = cleanText.localizedLowercase
        let lowerQuery = query.localizedLowercase
        
        guard let range = lowerText.range(of: lowerQuery) else {
            return String(cleanText.prefix(windowSize * 2))
        }
        
        let startDistance = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
        let safeStartOffset = max(0, startDistance - windowSize)
        
        let snippetStart = cleanText.index(cleanText.startIndex, offsetBy: safeStartOffset)
        
        let endDistance = cleanText.distance(from: range.upperBound, to: cleanText.endIndex)
        let safeEndOffset = min(endDistance, windowSize)
        
        let snippetEnd = cleanText.index(range.upperBound, offsetBy: safeEndOffset)
        
        var snippet = String(cleanText[snippetStart..<snippetEnd])
        
        if snippetStart > cleanText.startIndex {
            snippet = "..." + snippet
        }
        if snippetEnd < cleanText.endIndex {
            snippet += "..."
        }
        
        return snippet
    }
}
