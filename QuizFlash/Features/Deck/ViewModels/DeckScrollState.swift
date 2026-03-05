import SwiftUI

// MARK: - DeckScrollState
//
// Updated by an invisible anchor view placed just below the title.
// When the anchor scrolls above safeAreaTop, pillVisible = true.

@Observable
final class DeckScrollState {
    /// true when the title anchor has scrolled above the safe area top
    var pillVisible: Bool = false
}
