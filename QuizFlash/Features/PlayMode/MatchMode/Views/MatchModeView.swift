//
//  MatchModeView.swift
//  QuizFlash
//
//  Placeholder settings destination for the grid-based matching mode.
//

import SwiftUI

// MARK: - Match Mode View

/// Temporary settings destination for the upcoming question-and-answer matching mode.
struct MatchModeView: View {
    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets

    var body: some View {
        PlayModeSettingsScreen(deck: deck, mode: .match, safeAreaInsets: safeAreaInsets)
    }
}
