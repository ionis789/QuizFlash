//
//  SearchEngine.swift
//  QuizFlash
//
//  Created by Senior iOS Architect.
//

import Foundation
import SwiftData

@ModelActor
actor SearchEngine {
    
    /// Performs a tokenized, deep, case-insensitive, and diacritic-insensitive search.
    func performSearch(query: String) throws -> [DeckSearchResultItem] {
        // 1. Spargem query-ul în cuvinte separate (tokens)
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        
        let descriptor = FetchDescriptor<DeckModel>()
        let allDecks = try modelContext.fetch(descriptor)
        
        var results: [DeckSearchResultItem] = []
        let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        
        for deck in allDecks {
            var matchedCards: [MatchedCardInfo] = []
            
            // Verificăm dacă TOATE token-urile se află în titlul pachetului
            let titleMatches = tokens.allSatisfy { token in
                deck.title.range(of: token, options: searchOptions) != nil
            }
            
            for card in deck.cards {
                // Extragem absolut tot textul de pe față și spate într-un singur string sigur
                let fullText = extractAllText(from: card.frontZone) + " \n " + extractAllText(from: card.backZone)
                
                // Logica AND: Cardul este valid DOAR dacă include toate cuvintele căutate
                let cardMatches = tokens.allSatisfy { token in
                    fullText.range(of: token, options: searchOptions) != nil
                }
                
                if cardMatches {
                    let snippet = extractMultiTokenSnippet(from: fullText, tokens: tokens, options: searchOptions)
                    matchedCards.append(MatchedCardInfo(id: card.id, snippet: snippet))
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
    
    // MARK: - Deep Text Extraction
    private func extractAllText(from zone: ZoneModel) -> String {
        if zone.isLeaf { return zone.contentType == .text ? zone.text : "" }
        guard let children = zone.children else { return "" }
        return children.map { extractAllText(from: $0) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    
    // MARK: - Snippet Extraction Logic
    /// Extrage un fragment (snippet) centrat în jurul PRIMULUI token găsit
    private func extractMultiTokenSnippet(from text: String, tokens: [String], options: String.CompareOptions, windowSize: Int = 30) -> String {
        let cleanText = text.replacingOccurrences(of: "\n", with: " ")
        
        var earliestRange: Range<String.Index>? = nil
        
        // Găsim token-ul care apare cel mai devreme în text pentru a începe snippet-ul de acolo
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
        // Lăsăm fereastra de final mai largă pentru a crește șansele de a prinde și celelalte token-uri în preview
        let safeEndOffset = min(endDistance, windowSize + 30)
        let snippetEnd = cleanText.index(range.upperBound, offsetBy: safeEndOffset)
        
        var snippet = String(cleanText[snippetStart..<snippetEnd])
        
        if snippetStart > cleanText.startIndex { snippet = "..." + snippet }
        if snippetEnd < cleanText.endIndex { snippet += "..." }
        
        return snippet
    }
}
