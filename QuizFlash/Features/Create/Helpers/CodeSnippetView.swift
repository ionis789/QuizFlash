//
//  CodeSnippetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.02.2026.
//

import Foundation
import SwiftUI

// MARK: - Code Snippet View (Block Code)
struct CodeSnippetView: View {
    let rawText: String

    var body: some View {
        let (language, code) = parseCode(rawText)
        
        VStack(alignment: .leading, spacing: 0) {
            // Afișează limbajul de programare sus (dacă a fost detectat)
            if !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
            }
            
            // Scroll orizontal pentru liniile lungi de cod
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced)) // Font specific pentru cod
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.15)) // Același fundal gri care îți place la inline code!
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // Funcție de curățare: Extrage limbajul și șterge ``` dacă GPT le-a lăsat
    private func parseCode(_ input: String) -> (String, String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var lang = ""
        
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: .newlines)
            if let first = lines.first {
                lang = first.replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
                text = lines.dropFirst().joined(separator: "\n")
                if text.hasSuffix("```") {
                    text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return (lang, text)
    }
}
