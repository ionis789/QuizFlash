//
//  DeckCustomNavigationBar.swift
//  QuizFlash
//
//  Shared collapsible-title navigation bar adapter for the deck-detail screen.
//

import SwiftUI

// MARK: - DeckCustomNavigationBar

struct DeckCustomNavigationBar: View {
    @Environment(AppPreferences.self) private var appPreferences

    // MARK: - Inputs

    /// The deck whose title is shown in the collapsed pill.
    let deck: DeckModel
    /// Aggregate stats forwarded to `DeckHeroView` for the mastery ring.
    let stats: DeckStats
    /// The back-button label frozen at push time (never re-read from router state).
    let backLabel: String
    /// When non-`nil`, the search filter banner is active and the pill is hidden.
    let searchQuery: String?
    /// `true` when the parent view is in multi-card selection mode.
    let isSelecting: Bool
    /// Coordinate space used by shared chrome geometry callbacks.
    let coordinateSpaceName: String
    /// Active sort order shown in the native overflow menu.
    @Binding var sortOrder: SortOrder
    /// Active grouping mode shown beside the sort controls.
    @Binding var groupingMode: DeckCardGroupingMode

    // MARK: - Callbacks

    /// Called when the user taps the back button.
    let onBack: () -> Void
    /// Called when the user taps the "+" add button.
    let onAdd: () -> Void
    /// Called when the user taps "Select Cards" in the menu.
    let onStartSelection: () -> Void
    /// Called when the user taps the top checkmark while selecting.
    let onDoneSelection: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void
    /// Reports the resolved navigation bar height.
    let onHeightChange: (CGFloat) -> Void
    /// Reports the floating chrome bottom edge in the deck coordinate space.
    let onBottomChange: (CGFloat) -> Void

    // MARK: - Computed Properties

    @Environment(DeckScrollState.self) private var scrollState

    private var locale: Locale { appPreferences.resolvedLocale }
    private var shouldShowCollapsedTitle: Bool {
        searchQuery == nil && scrollState.pillVisible
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    // MARK: - Body

    var body: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: coordinateSpaceName,
            onHeightChange: onHeightChange,
            onBottomChange: onBottomChange
        ) {
            backButton
        } center: { maxTitleWidth in
            CollapsibleTitlePill(
                title: .verbatim(searchQuery == nil ? deck.title : ""),
                maxWidth: maxTitleWidth,
                isVisible: shouldShowCollapsedTitle,
                fallbackTitle: localized("Untitled Deck")
            )
        } trailing: {
            DeckActionOverlay(
                deck: deck,
                isSelecting: isSelecting,
                sortOrder: $sortOrder,
                groupingMode: $groupingMode,
                onAdd: onAdd,
                onStartSelection: onStartSelection,
                onDoneSelection: onDoneSelection,
                onExport: onExport
            )
        }
    }

    private var backButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "chevron.compact.left",
            accessibilityLabel: backLabel,
            action: onBack
        )
    }
}
