//
//  QuizModeView.swift
//  QuizFlash
//
//  Placeholder settings destination for the multiple-choice mode.
//

import SwiftUI

// MARK: - Quiz Mode View

/// Temporary settings destination for the upcoming multiple-choice quiz mode.
struct QuizModeView: View {
    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets

    var body: some View {
        PlayModeSettingsScreen(deck: deck, mode: .quiz, safeAreaInsets: safeAreaInsets)
    }
}
