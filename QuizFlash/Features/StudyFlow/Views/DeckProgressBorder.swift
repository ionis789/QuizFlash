//
//  DeckProgressBorder.swift
//  QuizFlash
//
//  Created by Ion Socol on 25.02.2026.
//

import SwiftUI

struct DeckProgressBorder: ViewModifier {
    let deck: DeckModel
    let cornerRadius: CGFloat

    private let baseLineWidth: CGFloat = 2
    private let masteredLineWidth: CGFloat = 3

    private var progress: Double {
        let totalCards = deck.cardCount
        guard totalCards > 0 else { return 0 }

        let seenCards = deck.cards.filter { !$0.reviewHistory.isEmpty }.count

        // PENTRU TESTARE: Decomentează linia de mai jos
        // return 0.65

        return Double(seenCards) / Double(totalCards)
    }

    private var isMastered: Bool {
        progress >= 1.0 && deck.cardCount > 0
    }

    private var activeLineWidth: CGFloat {
        isMastered ? masteredLineWidth : baseLineWidth
    }

    func body(content: Content) -> some View {
        content
        // 1. Bordura de fundal (Track-ul gol)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: baseLineWidth / 2)
                .stroke(Color.primary.opacity(0.15), lineWidth: baseLineWidth)
        )
        // 2. Bordura animată care indică progresul
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: activeLineWidth / 2)
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                isMastered
                    ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [ThemeManager.shared.accentColor.color, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                style: StrokeStyle(lineWidth: activeLineWidth, lineCap: .round)
            )
            // 🔴 ELIMINAT: .rotationEffect(.degrees(-90))
            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)
        )
            .shadow(color: isMastered ? .orange.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
    }
}

// Extensie utilitară pentru a-l folosi ușor în UI:
extension View {
    func withDeckProgressBorder(deck: DeckModel, cornerRadius: CGFloat = 20) -> some View {
        self.modifier(DeckProgressBorder(deck: deck, cornerRadius: cornerRadius))
    }
}
