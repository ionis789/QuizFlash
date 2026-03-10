//
//  FlashCardsModeSettingsView.swift
//  QuizFlash
//
//  Placeholder settings destination for the flashcards mode.
//

import SwiftUI

// MARK: - Flashcards Mode Settings View

/// Temporary settings destination for the flashcards play mode.
struct FlashCardsModeSettingsView: View {
    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets

    var body: some View {
        PlayModeSettingsScreen(deck: deck, mode: .flashcards, safeAreaInsets: safeAreaInsets)
    }
}
