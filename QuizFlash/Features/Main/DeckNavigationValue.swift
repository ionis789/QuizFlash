//
//  DeckNavigationValue.swift
//  QuizFlash
//
//  Abstract:
//  Type-safe, immutable navigation payload for pushing DeckView onto any NavigationStack.
//
//  Problem solved:
//  The previous architecture stored the DeckView back-button label in a single mutable
//  property on NavigationManager (`deckBackLabel`). All three NavigationStacks (Home,
//  Library, Create) shared that one property — whichever tab most recently pushed a deck
//  would overwrite the label for every other tab still holding a deck in its stack.
//
//  Concrete failure (reproduced in video):
//    1. User opens a deck from the Library tab  → deckBackLabel = "Library"
//    2. User switches to Home tab, opens any deck → deckBackLabel = "Home"  ← clobbers (1)
//    3. User switches back to Library tab (deck still live in stack)
//    4. DeckView reads deckBackLabel == "Home" → back button shows wrong label
//    5. During swipe-back, NavigationManager is invalidated; DeckView re-renders
//       with the recomputed correct value mid-gesture → visible label flip in video
//
//  Fix — encode context at push time:
//  The back label is frozen into DeckNavigationValue when the push is initiated.
//  Each NavigationPath entry carries its own independent label. No shared mutable
//  state. No cross-tab interference. No mid-animation recompute.
//

import SwiftData

/// Encapsulates all context needed to push `DeckView` onto a `NavigationStack`.
///
/// Conforms to `Hashable` so it can be stored in a `NavigationPath` and matched
/// by `.navigationDestination(for: DeckNavigationValue.self)`.
struct DeckNavigationValue: Hashable {

    /// The stable SwiftData identifier of the deck to display.
    let deckID: PersistentIdentifier

    /// The label shown in DeckView's back button, captured at push time.
    /// Examples: "Library", "Home", or a folder title such as "Math".
    let backLabel: String
}
