//
//  HighlightContext.swift
//  QuizFlash
//
//  Observable state object that carries a search query's highlight state
//  throughout the card display hierarchy during an active search session.
//
//  Extracted from `Domain/Models/ZoneModel.swift` where UI state does not belong.
//  Belongs in the Library feature layer because it is consumed exclusively by
//  search-result card views rendered from `SearchResultsView`.
//

import SwiftUI

// MARK: - Highlight Context

/// A single-use observable object that acts as the source of truth for
/// text-highlight state across all zones of a card during an active search session.
///
/// Inject one `HighlightContext` per card row in `SearchResultsView` and read it
/// from child zone views to determine whether and where to render highlights.
///
/// The object is irreversibly **dismissed** when the user navigates into the card —
/// highlights are no longer needed once the user enters the full editor.
@Observable
final class HighlightContext {

    // MARK: - Properties

    /// The raw search query string driving the highlight.
    let query: String

    /// Whether highlights have been permanently dismissed for this session.
    private(set) var isDismissed: Bool = false

    // MARK: - Initializer

    /// Creates a new `HighlightContext` for the given search query.
    /// - Parameter query: The search string whose tokens should be highlighted.
    init(query: String) {
        self.query = query
    }

    // MARK: - Actions

    /// Irreversibly dismisses all highlights for this context.
    ///
    /// Call this when the user navigates into the card editor so that
    /// highlights are removed and the context can be released.
    func dismiss() {
        isDismissed = true
    }

    // MARK: - Query Helpers

    /// Returns `true` if the given text contains at least one token from the search query
    /// and highlights have not been dismissed.
    ///
    /// - Parameter text: The plain text to test.
    func shouldHighlight(text: String) -> Bool {
        guard !isDismissed, !query.isEmpty, !text.isEmpty else { return false }
        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return tokens.contains { token in
            text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Generates a completely transparent `AttributedString` overlay with matched
    /// tokens tinted via `backgroundColor`, suitable for overlaying on top of a `TextField`.
    ///
    /// The foreground colour is forced to `.clear` so the underlying text remains
    /// visible while the highlight background is correctly positioned.
    ///
    /// - Parameters:
    ///   - text: The plain text to annotate.
    ///   - font: The font applied to the `TextField` being overlaid (must match exactly).
    ///   - highlightColor: The colour used as `backgroundColor` for matched token ranges.
    /// - Returns: An `AttributedString` with opaque text set to `.clear` and matched
    ///   token ranges tinted with `highlightColor.opacity(0.3)`.
    func generateOverlay(for text: String, font: Font, highlightColor: Color) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.font = font
        // Text must be completely invisible so it perfectly overlays the TextField.
        attrString.foregroundColor = .clear

        guard !isDismissed, !query.isEmpty else { return attrString }

        let tokens = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for token in tokens {
            var searchRange = attrString.startIndex..<attrString.endIndex
            while let matchRange = attrString[searchRange].range(
                of: token, options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                attrString[matchRange].backgroundColor = highlightColor.opacity(0.3)
                searchRange = matchRange.upperBound..<attrString.endIndex
            }
        }
        return attrString
    }
}
