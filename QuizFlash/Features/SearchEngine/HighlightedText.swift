//
//  HighlightedText.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//

import SwiftUI

// MARK: - Highlighted Text Component
// Safely iterates through a string to apply formatting to search matches.

struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .subheadline
    var baseColor: Color = .secondary
    
    private var highlightColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Text(text).font(font).foregroundStyle(baseColor)
        }
        
        return generateHighlightedText()
    }
    
    private func generateHighlightedText() -> Text {
        let lowerText = text.localizedLowercase
        let lowerQuery = query.localizedLowercase
        
        var resultText = Text("")
        var currentIndex = text.startIndex
        
        // Loop through all occurrences safely
        while let range = lowerText.range(of: lowerQuery, range: currentIndex..<text.endIndex) {
            let prefix = text[currentIndex..<range.lowerBound]
            let match = text[range]
            
            if !prefix.isEmpty {
                resultText = resultText + Text(prefix).font(font).foregroundStyle(baseColor)
            }
            
            // Apply Highlight styling
            resultText = resultText + Text(match).font(font.weight(.bold)).foregroundStyle(highlightColor)
            
            currentIndex = range.upperBound
        }
        
        // Append remaining text
        let suffix = text[currentIndex..<text.endIndex]
        if !suffix.isEmpty {
            resultText = resultText + Text(suffix).font(font).foregroundStyle(baseColor)
        }
        
        return resultText
    }
}
