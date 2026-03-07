//
//  DeckScrollState.swift
//  QuizFlash
//
//  Lightweight observable state object shared between DeckView's scroll content
//  and DeckHeroView via the SwiftUI environment.
//

import SwiftUI

// MARK: - DeckScrollState

/// Shared scroll-driven state injected into the view hierarchy via `.environment(scrollState)`.
///
/// Updated by an invisible anchor view placed just below the deck title in the scroll canvas.
/// When the anchor scrolls above the safe-area top edge, `pillVisible` becomes `true`,
/// causing `DeckHeroView` to animate its collapsed pill into view.
///
/// Uses `@Observable` (iOS 17+) — no `@Published` properties.
@Observable
final class DeckScrollState {
    /// `true` when the title anchor has scrolled above the safe-area top edge.
    var pillVisible: Bool = false
}
