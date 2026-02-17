//
//  HighlightedText.swift
//  QuizFlash
//
//  Created by Senior iOS Architect.
//

import SwiftUI

// MARK: - Centralized Highlight Engine
// Uses iOS 15+ AttributedString for highly performant, overlapping-safe highlights.
enum HighlightHelper {
    static func generateAttributedString(
        text: String,
        query: String,
        font: Font,
        baseColor: Color,
        highlightColor: Color
    ) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.font = font
        attrString.foregroundColor = baseColor
        
        let tokens = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.isEmpty { return attrString }
        
        for token in tokens {
            var searchRange = attrString.startIndex..<attrString.endIndex
            
            // Loop through all case/diacritic-insensitive matches for the current token
            while let matchRange = attrString[searchRange].range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                
                // 1. Add background highlight exactly like Apple Notes
                attrString[matchRange].backgroundColor = highlightColor.opacity(0.3)
                
                // 2. Make the text bold and prominent
                attrString[matchRange].font = font.weight(.bold)
                attrString[matchRange].foregroundColor = .primary
                
                // Move search cursor forward
                searchRange = matchRange.upperBound..<attrString.endIndex
            }
        }
        
        return attrString
    }
}

// MARK: - Highlighted Text Component (For Search List)
struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .subheadline
    var baseColor: Color = .secondary
    
    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        Text(HighlightHelper.generateAttributedString(
            text: text,
            query: query,
            font: font,
            baseColor: baseColor,
            highlightColor: accentColor
        ))
        // MARK: FIX - Force SwiftUI to completely rebuild the view when text updates.
        // This eradicates any stale "old position" caching bugs across list updates.
        .id(text + query)
    }
}
