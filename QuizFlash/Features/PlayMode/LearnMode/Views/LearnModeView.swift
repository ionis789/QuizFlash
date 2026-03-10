//
//  LearnModeView.swift
//  QuizFlash
//
//  Placeholder settings destination for the summary-style learn mode.
//

import SwiftUI

// MARK: - Learn Mode View

/// Temporary settings destination for the upcoming learn/report play mode.
struct LearnModeView: View {
    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets

    var body: some View {
        PlayModeSettingsScreen(deck: deck, mode: .learn, safeAreaInsets: safeAreaInsets)
    }
}
