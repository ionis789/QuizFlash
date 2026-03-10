//
//  WriteModeView.swift
//  QuizFlash
//
//  Placeholder settings destination for the manual answer input mode.
//

import SwiftUI

// MARK: - Write Mode View

/// Temporary settings destination for the upcoming typed-answer play mode.
struct WriteModeView: View {
    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets

    var body: some View {
        PlayModeSettingsScreen(deck: deck, mode: .write, safeAreaInsets: safeAreaInsets)
    }
}
