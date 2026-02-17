//
//  HighlightedText.swift
//  QuizFlash
//
//  Created by Senior iOS Architect.
//

import SwiftUI

// MARK: - Highlighted Text Component
// Supports Tokenized Multi-Word Highlighting with Range Merging
// (Apple Notes style)

struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .subheadline
    var baseColor: Color = .secondary
    
    private var highlightColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        let tokens = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard !tokens.isEmpty else {
            return Text(text).font(font).foregroundStyle(baseColor)
        }
        
        return generateHighlightedText(with: tokens)
    }
    
    private func generateHighlightedText(with tokens: [String]) -> Text {
        let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var matchRanges: [Range<String.Index>] = []
        
        // 1. Găsim TOATE intervalele din text unde există un match cu ORICARE din token-uri
        for token in tokens {
            var searchStartIndex = text.startIndex
            while searchStartIndex < text.endIndex,
                  let range = text.range(of: token, options: searchOptions, range: searchStartIndex..<text.endIndex) {
                matchRanges.append(range)
                searchStartIndex = range.upperBound // Avansăm cursorul
            }
        }
        
        if matchRanges.isEmpty {
            return Text(text).font(font).foregroundStyle(baseColor)
        }
        
        // 2. Sortăm și unim (Merge) intervalele care se suprapun
        // (Exemplu: dacă un token e "he" și altul e "hei", ele se vor suprapune pe același cuvânt)
        matchRanges.sort { $0.lowerBound < $1.lowerBound }
        var mergedRanges: [Range<String.Index>] = []
        
        for range in matchRanges {
            if let last = mergedRanges.last, last.upperBound >= range.lowerBound {
                // Dacă se suprapun, le extindem
                let newUpperBound = max(last.upperBound, range.upperBound)
                mergedRanges[mergedRanges.count - 1] = last.lowerBound..<newUpperBound
            } else {
                mergedRanges.append(range)
            }
        }
        
        // 3. Generăm view-ul Text final bucată cu bucată
        var resultText = Text("")
        var currentIndex = text.startIndex
        
        for range in mergedRanges {
            let prefix = text[currentIndex..<range.lowerBound]
            let match = text[range]
            
            // Adăugăm textul normal de dinaintea match-ului
            if !prefix.isEmpty {
                resultText = resultText + Text(prefix).font(font).foregroundStyle(baseColor)
            }
            
            // Adăugăm textul highlightat (îngroșat și cu culoarea accent)
            resultText = resultText + Text(match).font(font.weight(.bold)).foregroundStyle(highlightColor)
            
            currentIndex = range.upperBound
        }
        
        // Adăugăm orice a mai rămas din textul final
        let suffix = text[currentIndex..<text.endIndex]
        if !suffix.isEmpty {
            resultText = resultText + Text(suffix).font(font).foregroundStyle(baseColor)
        }
        
        return resultText
    }
}
